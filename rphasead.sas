/*****************************************************************************
 program ID:         \\eu.jnj.com\tibbedfsroot\sas\System\Dev\Adam\Templates\Rphasead.Sas
 Author:             Alain Smits   Tibotec Mechelen Ext.4325
 Created:            Feb, 2008
 Description:        Phase Analysis Data Set program


*****************************************************************************/


%put ------------------------------------------------------------------------;
%put -------------------------- Initialization ------------------------------;
%put ------------------------------------------------------------------------;

    %inc "\\eu.jnj.com\tibbedfsroot\sas\system\prd\util\init.sas";
    options nosource2 nosource spool;
    %let adamDefFile  = "\\eu.jnj.com\tibbedfsroot\sas\System\PRD\ADAM\AdamDef_v102.sas";
    %let adamMetaFile = "\\eu.jnj.com\tibbedfsroot\sas\System\PRD\ADAM\AdamMetadata_v102.sas";
    filename adampgm "\\eu.jnj.com\tibbedfsroot\sas\System\PRD\ADAM";
    %inc adampgm(dstore adamVarDef adamUserDef);
    filename phpgm "\\eu.jnj.com\tibbedfsroot\sas\System\PRD\ADAM\Macros";
    %inc phpgm(phasead);

%put ------------------------------------------------------------------------;
%put -------------------- Get Data and Set cutoffdate -----------------------;
%put ------------------------------------------------------------------------;

    %let cutoffDate=15jan2008;

    %unzip(zipfile=\\eu.jnj.com\tibbedfsroot\sas\Compound\TMC114\C214\DataManagement\Data\Version controlled\Interim locked\Week 96\Tabulations\Current\TMC114-C214-SAS-t-LOCK-20080213.zip,
           datasets=dm sv ds ex,
           libname=sds);

%put ------------------------------------------------------------------------;
%put ---------------- Obtain all relevant dates and flags -------------------;
%put ------------------------------------------------------------------------;

    %phInit(outds=allData010);

    %phPeriod(inds           = sds.ex,
              selection     = extrt='TMC114' and exdostxt ne '0',
              inStartDate   = exstdtc,
              inEndDate     = exendtc,
              outStartDate  = startDRV,
              outEndDate    = endDRV);

    %phPeriod(inds           = sds.ex,
              selection     = extrt='LPV/RTV' and exdostxt ne '0',
              inStartDate   = exstdtc,
              inEndDate     = exendtc,
              outStartDate  = startLPV,
              outEndDate    = endLPV);

    %phDate(inds    = sds.ds(where=(dsdecod='SUBJECT SIGNED INFORMED CONSENT ON')),
            inDate  = dsstdtc,
            outDate = informedConsent);

    %phDate(inds    = sds.sv(where=(visit=:'SCREENING - WEEK -4')),
            inDate  = svstdtc,
            outDate = screeningVisit);

    %phDate(inds    = sds.sv(where=(visit='BASELINE - DAY 1R')),
            inDate  = svstdtc,
            outDate = rolloverBaseline);

    %phDate(inds    = sds.sv(where=(visit='WITHDRAWAL-ROLLOVER')),
            inDate  = svstdtc,
            outDate = treatmentWithdrawal);

    %phDate(inds    = sds.sv(where=(visit='WITHDRAWAL R')),
            inDate  = svstdtc,
            outDate = rolloverWithdrawal);

    %phDate(inds    = sds.sv(where=(visit='WEEK 96')),
            inDate  = svstdtc,
            outDate = w96Visit);

    %phDate(inds    = sds.ds(where=(dscat in('WITHDRAWAL'))),
            inDate  = dsstdtc,
            outDate = withdrawalDSVisit);

    %phDate(inds    = sds.ds(where=(dscat in('SCREENING FAILURE','TRIAL TERMINATION','WITHDRAWAL'))),
            inDate  = dsstdtc,
            outDate = trialTermination);

    %phDate(inds    = sds.dm,
            inDate  = rfendtc,
            outDate = lastContact);

    %phFlag(inds      = sds.ds,
            criterium = dscat='WITHDRAWAL',
            flag      = flagTreatmentWithdrawal);

    %phFlag(inds      = sds.sv,
            criterium = visit = 'WEEK 96',
            flag      = flagWeek96);

    %phFlag(inds      = sds.ds,
            criterium = dscat='ROLL-OVER',
            flag      = flagRollover);

    %phFlag(inds      = sds.sv,
            criterium = visit = 'WITHDRAWAL R',
            flag      = flagRolloverWithdrawal);

    %phFlag(inds      = sds.sv,
            criterium = visit = 'EXTENSION VISIT',
            flag      = flagExtension);

    %phFlag(inds      = sds.ds,
            criterium = dsdecod='COMPLETED',
            flag      = flagCompleted);

    %phFlag(inds      = sds.ds,
            criterium = dsdecod=:'SUBJECT ONGOING',
            flag      = flagOngoing);

%put ------------------------------------------------------------------------;
%put -------------------- Perform phase logic per SAP -----------------------;
%put ------------------------------------------------------------------------;

    data allData;
       set allData010;
       where (startLPV or startDRV);
       termination=coalesce(lastContact,trialTermination);
       if not termination then termination="&cutoffDate"d;
       screening = min(informedConsent, screeningVisit);
       treatment = min(startDRV, startLPV);
       extension = ifn(flagExtension, w96Visit+1,.);
       rollover  = ifn(flagRollover, ifn(startLPV, startDRV, rolloverBaseline),.);
       select;
          when(flagExtension)           followup=ifn(flagTreatmentWithdrawal, coalesce(endDRV+3, treatmentWithdrawal+3),.);
          when(flagRollover)            followup=ifn(flagRolloverWithdrawal, coalesce(endDRV+3, rolloverWithdrawal+3),.);
          when(flagCompleted)           followup=coalesce(w96Visit+3, endDRV+3, endLPV+3);
          when(flagWeek96)              followup=coalesce(w96Visit+3, endDRV+3, endLPV+3);
          when(flagTreatmentWithdrawal) followup=coalesce(endDRV+3, endLPV+3, treatmentWithdrawal+3);
          when(flagOngoing)             followup=.;
       end;
       format termination screening treatment extension rollover followup yymmdd10.;
    run;

%put ------------------------------------------------------------------------;
%put ------------------------- Build phase data set -------------------------;
%put ------------------------------------------------------------------------;

    %phCreate(inds        = allData,
              termination = termination,
              outds       = phasead);
    %phDefine(phaseName = SCREENING,
              phasenum  = 0,
              startDate = screening);
    %phDefine(phaseName = TREATMENT,
              phasenum  = 1.1,
              startDate = treatment);
    %phDefine(phaseName = EXTENSION,
              phasenum  = 1.2,
              startDate = extension);
    %phDefine(phaseName = ROLLOVER,
              phasenum  = 2,
              startDate = rollover);
    %phDefine(phaseName = FOLLOW-UP,
              phasenum  = 3,
              startDate = followup);

%put ------------------------------------------------------------------------;
%put ---------------------- Create excel check list --------------------------;
%put ------------------------------------------------------------------------;

    %ds2excel(inds      = allData,
              if        = ,
              vars      = ,
              setcase   = ,
              order     = ,
              idvars    = usubjid,
              mode      = html,
              varnames  = N,
              merge     = OFF,
              filter    = ON,
              varorder  = DATA,
              colwidth  = 50pt,
              rotate    = 45,
              missing   = ' ',
              outfile   = "\\eu.jnj.com\tibbedfsroot\sas\System\DEV\TEST\rphasead - all dates.xls",
              zipfile   = ,
              sheetname = ,
              case      = asis,
              outds     = );

%put ------------------------------------------------------------------------;
%put ------------------------- Compare with ADAM -----------------------------;
%put ------------------------------------------------------------------------;

    libname adam '\\eu.jnj.com\tibbedfsroot\sas\Compound\TMC114\C214\Statistics\Data\WEEK 96\ADAM';

    %compare(leftds    = phasead,
             rightds   = adam.phasead,
             keyvars   = usubjid phasen phase,
             leftvars  = phstdt phendt,
             rightvars = phstdt phendt,
             outfile   = "\\eu.jnj.com\tibbedfsroot\sas\System\dev\ADAM\Templates\rphasead - compare with ADAM.html",
             title     = "Comparison of QC phasead and ADAM phasead",
             show      = D_ANY,
             maxrows   = 500,
             fuzz      = 0.0001);
