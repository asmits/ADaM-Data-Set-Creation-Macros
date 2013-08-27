/*****************************************************************************
 program ID:         \\eu.jnj.com\tibbedfsroot\sas\System\Dev\Adam\Templates\Rphasead.Sas
 Author:             Alain Smits   Tibotec Mechelen Ext.4325
 Created:            Feb, 2008
 Description:        Phase Analysis Data Set program


*****************************************************************************/

%put --------------------------------------------------------------------------------------------------------------------------------------------;
%put -------------------------------------------------------- Phase Macro Definitions ------------------------------------------------------------;
%put --------------------------------------------------------------------------------------------------------------------------------------------;
*** Set Time Unit (DAY | MINUTE);
    %let phTimeUnit=DAY;

*** Initialization of phase data collection: dates and flags;
    %macro phInit(outds=);
        %global _phasedata_outds;
        %let _phasedata_outds=&outds;
        %if %sysfunc(exist(&outds)) %then %do;
           proc datasets lib=work nolist;
              delete &outds/memtype=data;
           run;quit;
        %end;
    %mend;

*** Retrieves phase related dates;
    %macro phDate(inds    = ,
                  selection = ,
                  inDate  = ,
                  outDate = ,
                  select  =);
       %local dsid varnum rc;
       %let dsid=%sysfunc(open(%scan(&inds,1,%str(%()),i));
       %let varnum=%sysfunc(varnum(&dsid,&indate));
       %let rc=%sysfunc(close(&dsid));
       %if &varnum=0 %then %do;
          %put ERROR: The variable &indate does not exist in the data set &inds.;
          %abort;
       %end;
       %if %superq(selection) eq %then %let selection=1;
       data phDate010;
          set &inds;
       run;
       data phDate015;
          set phDate010;
          where (&selection) and not missing(&inDate);
          %if %upcase(&phTimeUnit)=DAY %then %do;
             &outDate=input(&indate,??yymmdd10.);
             format &outDate yymmdd10.;
          %end;
          %else %do;
             &outDate=sum(dhms(input(&indate,??yymmdd10.),0,0,0),input(scan(&indate,2,'T'),time.));
             format &outDate datetime.;
          %end;
          keep usubjid &outDate &indate;
          proc sort;by usubjid &outDate;
       run;
       data phDate020;
          set phDate015;
          by usubjid &outDate;
          %if %superq(select) ne %then %do;
             if &select..usubjid;
          %end;
          %else %do;
             if not(first.usubjid and last.usubjid) then do;
                error "ERROR: Data selection from &inds [&indate] does not yield one observation per subject,";
                error "either change the input data set or use the select option to select the first or last time point";
                error "ERROR: " usubjid= &outDate=;
             end;
          %end;
          /* check on incomplete days */
          if not missing(&indate) and missing(&outdate) then do;
             put "WARNING: Partial Date in &inds: &indate=" &indate +(-1) " for subject " usubjid +(-1) ".";
             %if %qupcase(&selection) ne 1 %then put "WARNING: Selection: %nrbquote(&selection)";;
             %if %qupcase(&select) ne %then put "WARNING: &select Date Selected";;
          end;
       run;
       data &_phasedata_outds;
          %if %sysfunc(exist(&_phasedata_outds)) %then %do;
             merge &_phasedata_outds phDate020;
          %end;
          %else %do;
             set phDate015;
          %end;
          by usubjid;
          if not(first.usubjid and last.usubjid) then do;
             error "ERROR: Data selection from &inds [&indate] does not yield one observation per patient";
             error "ERROR: " usubjid= &outDate=;
          end;
       run;
    %mend;

*** Creates flags;
    %macro phFlag(inds      = ,
                  criterium = ,
                  flag      = );
       %if %superq(criterium) eq %then %let criterium=1;
       data phFlag010;
          set &inds;
          where (&criterium);
          &flag=1;
          keep usubjid &flag;
          proc sort nodupkey;by usubjid;
       run;
       data &_phasedata_outds;
          %if %sysfunc(exist(&_phasedata_outds)) %then %do;
             merge &_phasedata_outds phFlag010;
          %end;
          %else %do;
             set phFlag010;
          %end;
          by usubjid;
       run;
    %mend;


*** Retrieves periods: first-start to last-stop;
    %macro phPeriod(inds         = ,
                    selection    = ,
                    InStartDate  = ,
                    InEndDate    = ,
                    outStartDate = ,
                    outEndDate   = );
       %if %superq(selection) eq %then %let selection=1;
       proc sort data=&inds out=phPeriod010;
          where &selection and not missing(&inStartDate);
          by usubjid &inStartDate;
       run;
       data phPeriod020;
          set phPeriod010;
          by usubjid &inStartDate;
          retain &outStartDate;
          format &outStartDate &outEndDate yymmdd10.;
          if first.usubjid then do;
             %if %upcase(&phTimeUnit)=DAY %then %do;
                &outStartDate=input(&inStartDate,??yymmdd10.);
                format &outStartDate yymmdd10.;
             %end;
             %else %do;
                &outStartDate=sum(dhms(input(&inStartDate,??yymmdd10.),0,0,0),input(scan(&inStartDate,2,'T'),time.));
                format &outStartDate datetime.;
             %end;
             /* check on incomplete days */
             if not missing(&inStartdate) and missing(&outStartdate) then do;
                put "WARNING: Partial Start Date in &inds: &inStartdate=" &instartdate +(-1) " for subject " usubjid +(-1) ".";
                put "WARNING: Selection: %nrbquote(&selection)";
             end;
          end;
          if last.usubjid;
          %if %upcase(&phTimeUnit)=DAY %then %do;
             &outEndDate=input(&inEndDate,??yymmdd10.);
             format &outEndDate yymmdd10.;
          %end;
          %else %do;
             &outEndDate=sum(dhms(input(&inEndDate,??yymmdd10.),0,0,0),input(scan(&inEndDate,2,'T'),time.));
             format &outEndDate datetime.;
          %end;
          /* check on incomplete days */
          if not missing(&inEnddate) and missing(&outEnddate) then do;
             put "WARNING: Partial End Date in &inds: &inEnddate=" &inEnddate +(-1) " for subject " usubjid +(-1) ".";
             put "WARNING: Selection: %nrbquote(&selection)";
          end;
          keep usubjid &outStartDate &outEndDate;
       run;
       data &_phasedata_outds;
          %if %sysfunc(exist(&_phasedata_outds)) %then %do;
             merge &_phasedata_outds phPeriod020;
          %end;
          %else %do;
             set phPeriod020;
          %end;
          by usubjid;
       run;
    %mend;



*** Creates the contiguous start and stop dates per phase based on phases defined with phDefine;
    %macro phCreate(inds  = ,
                    termination = ,
                    outds = phasead);
       %global _phaseOutds _phaseInds _phaseTermination;
       %let _phaseOutds=&outds;
       %let _phaseInds=&inds;
       %let _phaseTermination=&termination;
       %if %sysfunc(exist(_cumulative)) %then %do;
          proc datasets lib=work nolist;
             delete _cumulative/memtype=data;
          run;quit;
       %end;
    %mend;

*** Defines a phase;
    %macro phDefine(phaseName = ,
                    phaseNum  = ,
                    startDate = );
       data phdefine010;
          informat usubjid phase phstdt;
          set &_phaseInds;
          %adamvardef(phase phasen phstdt);
          phase   = symget('phaseName');
          phasen  = symgetn('phaseNum');
          phstdt  = (&startDate);
          keep usubjid phasen phase phstdt &_phaseTermination;
          proc sort;by usubjid;
       run;
       data _cumulative;
          %if %sysfunc(exist(_cumulative)) %then %do;
             set _cumulative phDefine010;
          %end;
          %else %do;
             set phDefine010;
          %end;
          where phstdt ne . and phstdt le &_phaseTermination;
          by usubjid;
       run;
       data phDefine020;
          set _cumulative;
          by usubjid phase notsorted;
          if first.phase;
       run;
       data phDefine030;
          set phDefine020;
          by usubjid;
       run;
       data &_phaseOutds;
          informat usubjid phasen phase phstdt phendt;
          set phDefine030;
          by usubjid;
          %adamvardef(phendt);
          nextPhaseObs = _n_+1;
          if not last.usubjid then do;
             set phDefine030(keep=phstdt rename=(phstdt=nextPhstdt)) point=nextPhaseObs;
             %if %upcase(&phTimeUnit)=DAY %then %do;
                phendt = nextPhstdt-1;
             %end;
             %else %do;
                phendt = nextPhstdt-60;
             %end;
          end;
          else phendt=&_phaseTermination;
          drop nextPhstdt;
       run;
    %mend;


