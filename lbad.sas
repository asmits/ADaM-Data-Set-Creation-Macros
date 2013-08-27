/*****************************************************************************
 Program ID:         AdLabTox
 Description:        Adds lab toxicity grading
 Assumption:         - Relies on an Excel file with the grading definitions
                       for an example see the DAIDS.xls file in the repository.
                     - Context variables such as sex, fasting or other conditions
                       have to match in excel file and input data set to allow proper
                       linkage. (e.g. Glucose ranges under matching conditions)
                     - relies on %adamvardef, a macro to define the variables with
                       the right attributes, as defined in the metadata library
 Uses macros:        %adamvardef, %fdolst, %fvexist
*****************************************************************************/

%macro labtox(labtoxfile  = ,
              inds        = ,
              outds       = );

   /* Read the tox grade definition excel file, to be adapted for compatibility with 64bit Windows */
   proc import out= _labtox010
             datafile= "&labtoxfile"
             dbms=excel replace;
             getnames=yes;
             mixed=yes;
   run;

   /* Parse the grading definitilon data set */
   data _labtox020;
     %adamvardef(vars=lbtestcd lbtoxnm);
     set _labtox010 (where = (not missing (lbtestcd)));
     lbtoxnm=strip(lbtoxnm);
     rename %fdolst(vars    =%fvexist(inds=_labtox010,vars=grade_1 grade_2 grade_3 grade_4),
                    stmt    =%nrstr(&item = _rangeg&itemno));;
     proc sort;by lbtestcd;
   run;
   proc contents data=_labtox020 (drop = _: LABORATORY_TEST ) noprint out=_labtox030 (keep=name varnum);run;
   proc contents data=&inds noprint out=_labtox040 (keep=name);run;
   data _null_;
     merge _labtox030 (in=tox where=(lowcase(name) not in ('lbtoxnm') ))
           _labtox040 (in=inds);
     by name;
     if tox and not inds 
      then put "USER WARNING: Variable " name " is missing in the input dataset &inds, "
                                  /"=> " name " is a conditional/context variable for the toxicity scaling";
   run;

   proc sql noprint;
      create table _labtox050 as
      select distinct lbtestcd as toxlbtestcd,upcase(lbstresu) as toxunit  from _labtox020
      order by toxlbtestcd,toxunit;
      create table _labtox060 as
      select distinct lbtestcd,upcase(lbstresu) as unit,lbtest from _inds;
      create table _labtox070 as
      select *
      from _labtox060 a full join _labtox050 b on
      a.lbtestcd = b.toxlbtestcd
      order by toxlbtestcd,toxunit;
      select name into :toxvars         separated by " "   from _labtox030 order by varnum;
      select name into :toxvars_notoxnm separated by " "   from _labtox030 (where=(lowcase(name) not in ('lbtoxnm') ))
      order by varnum;

   quit;
 *----   * check units (original or standard units) ----*;

   data _labtox06 _labtoxwrongunit;
      set _labtox05;
      by toxlbtestcd;
      where not missing(toxlbtestcd) and not missing(lbtestcd);
      retain found;
      if first.toxlbtestcd then found = 0;
      found = max(found,ifn(toxunit=unit or missing(toxunit) or toxunit="ULN",1,0));
      if last.toxlbtestcd and not found then do;
       output _labtoxwrongunit;
       put 'USER WAR' 'NING: Test ' lbtestcd ' not in data with same unit as in grading scale table eg. ' unit ' vs ' toxunit;
      end;
      else if last.toxlbtestcd and found then output _labtox06;
   run;


   %precision(inds= _inds ,outds=_precision,by=lbtestcd,var=lbstresc);

   data _labtox02;
      merge _labtox02   (in=in1)
            _precision (in=in2)
            ;
      by lbtestcd;
      round=_precision;
      if in1 and in2;
      proc sort; by &toxvars;
   run;

   data _labtox03;
      set _labtox02 ;
      by &toxvars notsorted;
      file "%sysfunc(pathname(work))\tox with rounding.sas";
      array _rangeg {*} _rangeg1-_rangeg4;
      length lo hi  $15;
      if _n_=1 then do;
         put '/* ------------------------------------------------------------------------------------------------*/';
         put "/*   Toxicity scale location  &labtoxfile  */";
         put '/* ------------------------------------------------------------------------------------------------*/';
      end;
      if first.%scan(&toxvars,-1) then do;


         put '/* ------------------------------------------------------------------------------------------------*/';
         put '/* ---------------------------- Toxgradings of : ' lbtestcd '--------------------------------------*/';
         put '/* ------------------------------------------------------------------------------------------------*/';
         %fdolst(vars    =&toxvars_notoxnm,
                 stmt    =%nrstr(if not missing(&item) then do;
                                  if &itemno=1 then put / "if lowcase(&item) = lowcase('" &item +(-1) "')" @ ;
                                  else              put " and lowcase(&item) = lowcase('" &item +(-1) "')" @;
                                 end;
                                 )
                  );
         put ' then do;';
         put '   select;';
      end;
      do i=4 to 1 by -1;
        if lowcase(_rangeg{i}) not in ('na','not available') and not missing(_rangeg{i}) then do;
          %fdolst(vars    =1 2,
                  vars2   =,
                  stmt    =%nrstr( l&item=lowcase(scan(compress(_rangeg{i}),&item,'-�'));
                                   if not missing(l&item ) then do;
                                    o&item=ifc((substr(l&item,1,1) in ('<','>')),substr(l&item,1,1),'');
                                    factor=ifc(index(l&item,'xlln'),cats('/ round(lbstnrlo,',put(round,best.),')'),'');
                                    factor=ifc(index(l&item,'xuln'),cats('/ round(lbstnrhi,',put(round,best.),')'),'');
                                    l&item=tranwrd(l&item,'xlln','');
                                    l&item=tranwrd(l&item,'xuln','');
                                    l&item=tranwrd(l&item,'lln','lbstnrlo');
                                    l&item=tranwrd(l&item,'uln','lbstnrhi');
                                    l&item=compress(l&item,'<>');
                                   end;
                                  )
                  );

          lo = l1; loc=ifc(missing(o1),'<=','<');
          hi = l2; hic=ifc(missing(o2),'<=','<');

          if l1 in ('lbstnrlo') then  do ;
            lo = l2; loc=ifc(missing(o2),'<=','<');
            hi = l1; hic=ifc(missing(o1),'<=','<');
          end;
          else if missing(l2) then do;
            if o1 = '<' then do;
              hi = l1; hic=ifc(missing(l1),'<=','<');
              lo = ''; loc='';
            end;
            else if o1 = '>' then do;
              hi = ''; hic='';
            end;
          end;
          else if notdigit(l1) and notdigit(l2) and not missing(l2)
                and not (l1  in ('lbstnrhi','lbstnrlo') or l2  in ('lbstnrhi','lbstnrlo')) then do ;
            l1n=input( compress(l1),best.) ;
            l2n=input(strip(l2),best.);
            if l1n > l2n then do;
              lo = l2; loc=ifc(missing(o2),'<=','<');
              hi = l1; hic=ifc(missing(o1),'<=','<');
            end;
          end;
          if l1  in ('lbstnrhi','lbstnrlo') or l2  in ('lbstnrhi','lbstnrlo') then do;
           put '/* ------lbstnrhi or  lbstnrlo : can be Upper or lower limit=> not known in advance---------------*/';

           put '      when( ' hi +(-1)  hic  'round(lbstresn,' round +(-1) ') '  factor loc lo +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';
           put '      when( ' lo +(-1)  loc  'round(lbstresn,' round +(-1) ') '  factor hic hi +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';
          end;
          else do;
           put '      when( ' lo +(-1)  loc  'round(lbstresn,' round +(-1) ') '  factor hic hi +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';

          end;
          output;
        end;
      end;
      if last.%scan(&toxvars,-1) then do;
         put '      otherwise do;';
         put '        lbtox="GRADE 0"; lbtoxn=0;';
         put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
         put '        else lbtoxnm = "' lbtoxnm '";';
         put '      end;';
         put '   end;';
         put '   output;';
         put '   _written=1;';
         put 'end;';
      end;
   run;

   data _labtox03;
      set _labtox02 ;
      by &toxvars notsorted;
      file "%sysfunc(pathname(work))\tox without rounding.sas";
      array _rangeg {*} _rangeg1-_rangeg4;
      length lo hi  $15;
      if _n_=1 then do;
         put '/* ------------------------------------------------------------------------------------------------*/';
         put "/*   Toxicity scale location  &labtoxfile  */";
         put '/* ------------------------------------------------------------------------------------------------*/';
      end;
      if first.%scan(&toxvars,-1) then do;


         put '/* ------------------------------------------------------------------------------------------------*/';
         put '/* ---------------------------- Toxgradings of : ' lbtestcd '--------------------------------------*/';
         put '/* ------------------------------------------------------------------------------------------------*/';
         %fdolst(vars    =&toxvars_notoxnm,
                 stmt    =%nrstr(if not missing(&item) then do;
                                  if &itemno=1 then put / "if lowcase(&item) = lowcase('" &item +(-1) "')" @ ;
                                  else              put " and lowcase(&item) = lowcase('" &item +(-1) "')" @;
                                 end;
                                 )
                  );
         put ' then do;';
         put '   select;';
      end;
      do i=4 to 1 by -1;
        if lowcase(_rangeg{i}) not in ('na','not available') and not missing(_rangeg{i}) then do;
          %fdolst(vars    =1 2,
                  vars2   =,
                  stmt    =%nrstr( l&item=lowcase(scan(compress(_rangeg{i}),&item,'-�'));
                                   if not missing(l&item ) then do;
                                    o&item=ifc((substr(l&item,1,1) in ('<','>')),substr(l&item,1,1),'');
                                    factor=ifc(index(l&item,'xlln'),'/ lbstnrlo','');
                                    factor=ifc(index(l&item,'xuln'),'/ lbstnrhi','');
                                    l&item=tranwrd(l&item,'xlln','');
                                    l&item=tranwrd(l&item,'xuln','');
                                    l&item=tranwrd(l&item,'lln','lbstnrlo');
                                    l&item=tranwrd(l&item,'uln','lbstnrhi');
                                    l&item=compress(l&item,'<>');
                                   end;
                                  )
                  );

          lo = l1; loc=ifc(missing(o1),'<=','<');
          hi = l2; hic=ifc(missing(o2),'<=','<');

          if l1 in ('lbstnrlo') then  do ;
            lo = l2; loc=ifc(missing(o2),'<=','<');
            hi = l1; hic=ifc(missing(o1),'<=','<');
          end;
          else if missing(l2) then do;
            if o1 = '<' then do;
              hi = l1; hic=ifc(missing(l1),'<=','<');
              lo = ''; loc='';
            end;
            else if o1 = '>' then do;
              hi = ''; hic='';
            end;
          end;
          else if notdigit(l1) and notdigit(l2) and not missing(l2)
                and not (l1  in ('lbstnrhi','lbstnrlo') or l2  in ('lbstnrhi','lbstnrlo')) then do ;
            l1n=input( compress(l1),best.) ;
            l2n=input(strip(l2),best.);
            if l1n > l2n then do;
              lo = l2; loc=ifc(missing(o2),'<=','<');
              hi = l1; hic=ifc(missing(o1),'<=','<');
            end;
          end;
          if l1  in ('lbstnrhi','lbstnrlo') or l2  in ('lbstnrhi','lbstnrlo') then do;

           put '/* ------lbstnrhi or  lbstnrlo : can be Upper or lower limit=> not known in advance---------------*/';
           put '      when( ' hi +(-1)  hic  ' lbstresn '  factor loc lo +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';
           put '      when( ' lo +(-1)  loc  ' lbstresn '  factor hic hi +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';
          end;
          else do;
           put '      when( ' lo +(-1)  loc  ' lbstresn '  factor hic hi +(-1)  ') do;';
           put '        lbtox="GRADE ' i '"; lbtoxn=' i ';';
           put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
           put '        else lbtoxnm = "' lbtoxnm '";';
           put '      end;';

          end;
          output;
        end;
      end;
      if last.%scan(&toxvars,-1) then do;
         put '      otherwise do;';
         put '        lbtox="GRADE 0"; lbtoxn=0;';
         put '        if "  " = "' lbtoxnm '" then lbtoxnm=lbtest;';
         put '        else lbtoxnm = "' lbtoxnm '";';
         put '      end;';
         put '   end;';
         put '   output;';
         put '   _written=1;';
         put 'end;';
      end;
   run;



   data _labtox04;
      set _inds;
      %adamvardef(lbtox lbtoxn lbtoxnm);
      options source2;
      _written=0;
      if _bslmedian = 'Y' then do;
         %inc "%sysfunc(pathname(work))\tox without rounding.sas";
      end;
      else if lbstresn ne . then do;
         %inc "%sysfunc(pathname(work))\tox with rounding.sas";
      end;
      if not _written then output;
      drop _written;
   run;

   *no toxgrades*;
   data _labtox05;
      set _labtox04;
      _no = 1;
      _temp   = scan(lbstnrc,_no,' ');
      do while (not missing(_temp));
        if anydigit(_temp) then do;
          if      index(_temp,'<') then  lbstnrhi=input(compress(_temp,'<'),best.);
          else if index(_temp,'>') then  lbstnrlo=input(compress(_temp,'>'),best.);
          else                           lbstnrhi=input(_temp,best.);
        end;
        _no+1;
        _temp   = scan(lbstnrc,_no,' ');
      end;

       if lbtox eq '' and  (not missing(lbstnrlo) or not missing(lbstnrhi)) then do;
          lbtoxnm = lbtest;
          if not missing(lbstresn) then do;
            if lbstresn < max(lbstnrlo,0) then do;
               lbtox  = 'BELOW';
               lbtoxn = 5;
            end;
            else if lbstnrhi ne . then do;
               if lbstresn > lbstnrhi then do;
                  lbtox  = 'ABOVE';
                  lbtoxn = 7;
               end;
               else do;
                  lbtox  = 'WITHIN';
                  lbtoxn = 6;
               end;
            end;
          end;
       end;
       _key=_n_;
       _lbtoxn_worst=ifn(lbtoxn in (5 7),7,lbtoxn);
   run;

*** worst tox grade;

    proc sort data = _labtox05 (where=(analtptn>0 and phasen>0 and not missing(lbtoxnm))
                                keep=usubjid phasen lbtoxnm _lbtoxn_worst analtptn _key)
              out  = _labtox06  (drop =analtptn) ;
       by usubjid phasen lbtoxnm descending _lbtoxn_worst;
    run;

    data _labtox07;
       set _labtox06 (drop = _key);
       by usubjid phasen lbtoxnm descending _lbtoxn_worst;
       if first.lbtoxnm;
    run;

    data  _labtox08;
      merge _labtox06 (in=in1 rename = _lbtoxn_worst = _lbtoxn_worst_base)
            _labtox07 (in=in2);
      by usubjid phasen lbtoxnm;
      if in2 then do;
        if not missing(_lbtoxn_worst) and _lbtoxn_worst = _lbtoxn_worst_base then lbworst="Y";
        else                                                                   lbworst="N";
      end;
      proc sort;by _key;
    run;

    data &outds;
      merge _labtox08 (keep=_key lbworst)
            _labtox05 (in=in1);
      by _key ;
      if in1;
      drop _:;
    run;




   options nosource2;
%mend;
