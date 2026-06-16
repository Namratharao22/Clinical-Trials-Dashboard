/*===========================================================================
  PROJECT  : Clinical Trial Analytics Dashboard
  PROTOCOL : NV-2024-CT | Phase III RCT | Oncology
  AUTHOR   : Namratha Vardhineni
  DATE     : June 2026
  PURPOSE  : Generate ADSL, ADAE, TFL Tracker datasets and
             AE Summary + Enrollment Summary TFL outputs
  STANDARDS: CDISC ADaM | CTCAE v5.0
=============================================================================
  CONTENTS
  --------
  SECTION 1 : Setup — library and macro variables
  SECTION 2 : ADSL — Subject-Level Analysis Dataset
  SECTION 3 : ADAE — Adverse Event Analysis Dataset
  SECTION 4 : TFL Tracker dataset
  SECTION 5 : Enrollment summary by arm and site
  SECTION 6 : AE summary table by SOC and CTCAE grade (TFL output)
  SECTION 7 : Validation checks
===========================================================================*/


/*===========================================================================
  SECTION 1 : SETUP
===========================================================================*/

/* Define libraries */
libname adam    "C:\Projects\NV2024CT\Data\ADaM";
libname tfldata "C:\Projects\NV2024CT\Data\TFL";
libname output  "C:\Projects\NV2024CT\Output";

/* Global macro variables */
%let protocol  = NV-2024-CT;
%let phase     = III;
%let target_n  = 1320;
%let cutoff_dt = 16JUN2026;
%let author    = Namratha Vardhineni;

/* Output options */
options nodate nonumber ls=200 ps=max nofmterr;
ods noresults;

/* Formats used across datasets */
proc format;
  value $armfmt
    'Treatment' = 'Treatment Arm'
    'Placebo'   = 'Placebo Arm';

  value $statusfmt
    'Completed'         = 'Completed'
    'Active'            = 'Ongoing'
    'Discontinued'      = 'Discontinued'
    'Screening Failure' = 'Screen Failure';

  value $sexfmt
    'M' = 'Male'
    'F' = 'Female';

  value $serfmt
    'Y' = 'Serious'
    'N' = 'Non-serious';

  value gradefmt
    1 = 'Grade 1 (Mild)'
    2 = 'Grade 2 (Moderate)'
    3 = 'Grade 3 (Severe)'
    4 = 'Grade 4 (Life-threatening)';

  value $resfmt
    'Y' = 'Resolved'
    'N' = 'Ongoing';

  value $tflstsfmt
    'Validated'    = 'Validated'
    'In QC Review' = 'In QC Review'
    'Pending'      = 'Pending';
run;


/*===========================================================================
  SECTION 2 : ADSL — Subject-Level Analysis Dataset
  One row per subject. Follows CDISC ADaM ADSL conventions.
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 2.1 : Create raw subject records with demographic and trial variables
---------------------------------------------------------------------------*/
data adsl_raw;
  length USUBJID   $12
         STUDYID   $12
         SITE      $30
         ARM       $12
         ARMCD     $4
         SEX       $1
         RACE      $40
         STATUS    $20
         DTHFL     $1
         PROTOCOL  $12
         PHASE     $5
         SAFFL     $1
         ITTFL     $1
         PPROTFL   $1;

  STUDYID  = "&protocol";
  PROTOCOL = "&protocol";
  PHASE    = "&phase";

  /* Seed for reproducibility */
  call streaminit(42);

  /* Site names */
  array sites{6} $30 _temporary_ (
    'USF Health Tampa'
    'Mayo Clinic AZ'
    'MD Anderson TX'
    'Cleveland Clinic'
    'Johns Hopkins'
    'Stanford Medicine'
  );

  /* Arms */
  array arms{2} $12 _temporary_ ('Treatment' 'Placebo');
  array armcds{2} $4 _temporary_ ('TRT' 'PBO');

  /* Race categories */
  array races{5} $40 _temporary_ (
    'White'
    'Black or African American'
    'Asian'
    'Hispanic or Latino'
    'Other'
  );

  /* Status categories with probability weights */
  /* Completed=62%, Active=25%, Discontinued=8%, Screening Failure=5% */
  array statuses{4} $20 _temporary_ (
    'Completed'
    'Active'
    'Discontinued'
    'Screening Failure'
  );

  do i = 1 to 200;
    USUBJID = cats('NV2024-', put(i, z4.));

    /* Site — random across 6 sites */
    site_idx = ceil(rand('Uniform') * 6);
    SITE     = sites{site_idx};
    SITEID   = put(site_idx, 1.);

    /* ARM — roughly 50/50 split */
    arm_idx  = ceil(rand('Uniform') * 2);
    ARM      = arms{arm_idx};
    ARMCD    = armcds{arm_idx};

    /* Age — normal distribution centered at 52, clipped 18-80 */
    AGE = round(rand('Normal', 52, 12));
    if AGE < 18 then AGE = 18;
    if AGE > 80 then AGE = 80;

    /* Sex — ~52% Female */
    u = rand('Uniform');
    if u <= 0.52 then SEX = 'F'; else SEX = 'M';

    /* Race — weighted probabilities */
    u2 = rand('Uniform');
    if      u2 <= 0.55 then RACE = races{1};
    else if u2 <= 0.73 then RACE = races{2};
    else if u2 <= 0.87 then RACE = races{3};
    else if u2 <= 0.97 then RACE = races{4};
    else                     RACE = races{5};

    /* Enrollment month Jan–Jun 2026 */
    ENROLL_MONTH = ceil(rand('Uniform') * 6);
    ENROLL_YEAR  = 2026;
    RFSTDTC      = mdy(ENROLL_MONTH, ceil(rand('Uniform')*28), ENROLL_YEAR);
    format RFSTDTC date9.;

    /* Status — weighted */
    u3 = rand('Uniform');
    if      u3 <= 0.62 then STATUS = statuses{1};
    else if u3 <= 0.87 then STATUS = statuses{2};
    else if u3 <= 0.95 then STATUS = statuses{3};
    else                     STATUS = statuses{4};

    /* Death flag — only for discontinued subjects */
    DTHFL = 'N';
    if STATUS = 'Discontinued' and rand('Uniform') <= 0.05 then DTHFL = 'Y';

    /* Analysis flags */
    SAFFL   = 'Y';  /* All enrolled subjects in safety population */
    ITTFL   = 'Y';  /* Intent-to-treat population */
    if STATUS = 'Screening Failure'
      then PPROTFL = 'N';
      else PPROTFL = 'Y';

    output;
  end;

  drop i u u2 u3 site_idx arm_idx;
run;

/*---------------------------------------------------------------------------
  Step 2.2 : Sort and apply labels — CDISC ADaM ADSL conventions
---------------------------------------------------------------------------*/
proc sort data=adsl_raw out=adam.adsl;
  by USUBJID;
run;

data adam.adsl;
  set adam.adsl;
  label
    USUBJID      = 'Unique Subject Identifier'
    STUDYID      = 'Study Identifier'
    SITE         = 'Investigator Site Name'
    SITEID       = 'Site Identifier'
    ARM          = 'Description of Planned Arm'
    ARMCD        = 'Planned Arm Code'
    AGE          = 'Age at Enrollment (Years)'
    SEX          = 'Sex'
    RACE         = 'Race'
    STATUS       = 'Subject Disposition Status'
    DTHFL        = 'Death Flag'
    RFSTDTC      = 'Date of First Study Treatment'
    ENROLL_MONTH = 'Enrollment Month (1-6)'
    ENROLL_YEAR  = 'Enrollment Year'
    PROTOCOL     = 'Protocol Identifier'
    PHASE        = 'Trial Phase'
    SAFFL        = 'Safety Population Flag'
    ITTFL        = 'Intent-to-Treat Population Flag'
    PPROTFL      = 'Per-Protocol Population Flag';
run;

/* Quick check */
proc freq data=adam.adsl;
  tables ARM STATUS SEX / nocum nopercent;
  title "ADSL — Frequency Check | Protocol: &protocol";
run;
title;

proc means data=adam.adsl n mean std min max;
  var AGE;
  title "ADSL — Age Summary";
run;
title;


/*===========================================================================
  SECTION 3 : ADAE — Adverse Event Analysis Dataset
  One row per adverse event. Follows CDISC ADaM ADAE conventions.
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 3.1 : Define SOC, preferred terms, and AE counts
---------------------------------------------------------------------------*/

/* SOC reference table */
data soc_ref;
  length SOC $50 AETERM $50;
  input SOC $ 1-50 AETERM $ 51-100 SOC_COUNT;
  datalines;
Gastrointestinal disorders                        Nausea                                            28
Gastrointestinal disorders                        Vomiting                                          26
Gastrointestinal disorders                        Diarrhea                                          32
Gastrointestinal disorders                        Abdominal pain                                    30
Gastrointestinal disorders                        Constipation                                      26
Nervous system disorders                          Headache                                          22
Nervous system disorders                          Dizziness                                         19
Nervous system disorders                          Peripheral neuropathy                             21
Nervous system disorders                          Insomnia                                          18
Nervous system disorders                          Tremor                                            18
General disorders & admin site                    Fatigue                                           25
General disorders & admin site                    Pyrexia                                           18
General disorders & admin site                    Injection site reaction                           20
General disorders & admin site                    Malaise                                           14
General disorders & admin site                    Edema                                             10
Respiratory & thoracic                            Cough                                             14
Respiratory & thoracic                            Dyspnea                                           12
Respiratory & thoracic                            Nasopharyngitis                                   11
Respiratory & thoracic                            Upper respiratory infection                        9
Respiratory & thoracic                            Rhinorrhea                                         8
Skin & subcutaneous tissue                        Rash                                              14
Skin & subcutaneous tissue                        Pruritus                                          10
Skin & subcutaneous tissue                        Alopecia                                           8
Skin & subcutaneous tissue                        Dry skin                                           5
Skin & subcutaneous tissue                        Urticaria                                          4
Cardiac disorders                                 Palpitations                                       8
Cardiac disorders                                 Tachycardia                                        7
Cardiac disorders                                 Hypertension                                       6
Cardiac disorders                                 Chest pain                                         5
Cardiac disorders                                 Bradycardia                                        3
Hepatobiliary disorders                           ALT increased                                      7
Hepatobiliary disorders                           AST increased                                      6
Hepatobiliary disorders                           Hepatotoxicity                                     4
Hepatobiliary disorders                           Jaundice                                           3
Hepatobiliary disorders                           Cholestasis                                        2
;
run;

/*---------------------------------------------------------------------------
  Step 3.2 : Expand SOC reference into individual AE records
             and join to ADSL for subject-level variables
---------------------------------------------------------------------------*/
data adae_expanded;
  call streaminit(123);
  set soc_ref;

  do j = 1 to SOC_COUNT;

    /* Assign a random subject from ADSL */
    SUBJ_IDX = ceil(rand('Uniform') * 200);
    USUBJID  = cats('NV2024-', put(SUBJ_IDX, z4.));

    /* CTCAE grade — weighted: Grade1=49%, 2=30%, 3=15%, 4=6% */
    u = rand('Uniform');
    if      u <= 0.49 then CTCAE_GRADE = 1;
    else if u <= 0.79 then CTCAE_GRADE = 2;
    else if u <= 0.94 then CTCAE_GRADE = 3;
    else                    CTCAE_GRADE = 4;

    /* Serious AE flag — Grade 3+ */
    if CTCAE_GRADE >= 3 then AESER = 'Y';
    else                     AESER = 'N';

    /* Resolution — 78% resolved */
    u2 = rand('Uniform');
    if u2 <= 0.78 then AEOUT = 'RESOLVED';
    else               AEOUT = 'NOT RESOLVED';

    /* Onset week from first dose */
    AESTDY = ceil(rand('Uniform') * 24);

    /* Relationship to study drug */
    u3 = rand('Uniform');
    if      u3 <= 0.45 then AEREL = 'RELATED';
    else if u3 <= 0.70 then AEREL = 'POSSIBLY RELATED';
    else                     AEREL = 'NOT RELATED';

    /* Action taken */
    if CTCAE_GRADE >= 3 then AEACN = 'DOSE REDUCED';
    else if CTCAE_GRADE = 2 then AEACN = 'DOSE NOT CHANGED';
    else                         AEACN = 'DOSE NOT CHANGED';

    AE_SEQ + 1;
    AEID = cats('AE-', put(AE_SEQ, z4.));

    output;
  end;

  drop j u u2 u3 SUBJ_IDX SOC_COUNT;
run;

/*---------------------------------------------------------------------------
  Step 3.3 : Merge with ADSL to bring in ARM, SITE, population flags
---------------------------------------------------------------------------*/
proc sort data=adae_expanded; by USUBJID; run;
proc sort data=adam.adsl out=adsl_merge
  (keep=USUBJID ARM SITE SAFFL ITTFL STUDYID PROTOCOL PHASE);
  by USUBJID;
run;

data adam.adae;
  merge adae_expanded (in=inAE)
        adsl_merge    (in=inADSL);
  by USUBJID;
  if inAE;  /* Keep all AE records; flag if no ADSL match */

  STUDYID  = "&protocol";
  PROTOCOL = "&protocol";

  label
    AEID        = 'Unique Adverse Event Identifier'
    USUBJID     = 'Unique Subject Identifier'
    STUDYID     = 'Study Identifier'
    ARM         = 'Treatment Arm'
    SITE        = 'Investigator Site'
    SOC         = 'System Organ Class (MedDRA)'
    AETERM      = 'Adverse Event Preferred Term'
    CTCAE_GRADE = 'CTCAE Grade (v5.0)'
    AESER       = 'Serious Adverse Event Flag (Y/N)'
    AEREL       = 'Relationship to Study Drug'
    AEACN       = 'Action Taken with Study Treatment'
    AEOUT       = 'Outcome of Adverse Event'
    AESTDY      = 'Study Day of AE Onset'
    SAFFL       = 'Safety Population Flag'
    PROTOCOL    = 'Protocol Identifier';
run;

/* Validation check */
proc freq data=adam.adae;
  tables CTCAE_GRADE AESER ARM / nocum nopercent;
  title "ADAE — Grade and Seriousness Check | Protocol: &protocol";
run;
title;


/*===========================================================================
  SECTION 4 : TFL TRACKER DATASET
===========================================================================*/

data tfldata.tfl_tracker;
  length TFL_ID       $8
         TYPE         $8
         TITLE        $80
         PROGRAM      $30
         STATUS       $15
         VALIDATED_BY $10
         QC_BY        $15
         DOMAIN       $8
         PROTOCOL     $12;

  PROTOCOL = "&protocol";

  call streaminit(99);

  /* --- TABLES (84 total) --- */
  array tbl_titles{10} $80 _temporary_ (
    'Summary of Demographics and Baseline Characteristics'
    'Subject Disposition'
    'Adverse Events by System Organ Class and Preferred Term'
    'Adverse Events by CTCAE Grade'
    'Serious Adverse Events'
    'Laboratory Abnormalities — Hematology'
    'Laboratory Abnormalities — Chemistry'
    'Vital Signs Summary'
    'Primary Efficacy Endpoint'
    'Pharmacokinetic Parameters Summary'
  );
  array tbl_domains{10} $8 _temporary_ (
    'ADSL' 'ADSL' 'ADAE' 'ADAE' 'ADAE'
    'ADLB' 'ADLB' 'ADVS' 'ADEFF' 'ADPK'
  );

  do i = 1 to 84;
    TFL_ID  = cats('T', put(i, z3.));
    TYPE    = 'Table';
    idx     = mod(i-1, 10) + 1;
    TITLE   = cats(tbl_titles{idx}, ' — Table ', put(i, 3.));
    PROGRAM = cats('t_', put(i, z3.), '.sas');
    DOMAIN  = tbl_domains{idx};

    u = rand('Uniform');
    if      u <= 0.84 then do; STATUS = 'Validated';    VALIDATED_BY = 'NV'; QC_BY = 'Programmer2'; end;
    else if u <= 0.94 then do; STATUS = 'In QC Review'; VALIDATED_BY = '';   QC_BY = 'Programmer2'; end;
    else                   do; STATUS = 'Pending';       VALIDATED_BY = '';   QC_BY = '';             end;

    output;
  end;

  /* --- FIGURES (36 total) --- */
  array fig_titles{8} $80 _temporary_ (
    'Patient Enrollment Trend by Arm'
    'Kaplan-Meier Overall Survival Curve'
    'Adverse Event Waterfall Plot'
    'Forest Plot — Subgroup Analysis'
    'Pharmacokinetic Profile by Dose'
    'Biomarker Correlation — Scatter Plot'
    'Box Plot — Efficacy by Arm and Visit'
    'Swimmer Plot — Individual Patient Response'
  );

  do i = 1 to 36;
    TFL_ID  = cats('F', put(i, z3.));
    TYPE    = 'Figure';
    idx     = mod(i-1, 8) + 1;
    TITLE   = cats(fig_titles{idx}, ' — Figure ', put(i, 3.));
    PROGRAM = cats('f_', put(i, z3.), '.sas');
    DOMAIN  = 'ADEFF';

    u = rand('Uniform');
    if      u <= 0.80 then do; STATUS = 'Validated';    VALIDATED_BY = 'NV'; QC_BY = 'Programmer2'; end;
    else if u <= 0.94 then do; STATUS = 'In QC Review'; VALIDATED_BY = '';   QC_BY = 'Programmer2'; end;
    else                   do; STATUS = 'Pending';       VALIDATED_BY = '';   QC_BY = '';             end;

    output;
  end;

  /* --- LISTINGS (52 total) --- */
  array lst_titles{7} $80 _temporary_ (
    'Listing of Subject Disposition'
    'Listing of Protocol Deviations'
    'Listing of Serious Adverse Events'
    'Listing of Laboratory Abnormalities'
    'Listing of Vital Sign Abnormalities'
    'Listing of Discontinued Subjects'
    'Listing of Dose Modifications'
  );
  array lst_domains{7} $8 _temporary_ (
    'ADSL' 'ADSL' 'ADAE' 'ADLB' 'ADVS' 'ADSL' 'ADEX'
  );

  do i = 1 to 52;
    TFL_ID  = cats('L', put(i, z3.));
    TYPE    = 'Listing';
    idx     = mod(i-1, 7) + 1;
    TITLE   = cats(lst_titles{idx}, ' — Listing ', put(i, 3.));
    PROGRAM = cats('l_', put(i, z3.), '.sas');
    DOMAIN  = lst_domains{idx};

    u = rand('Uniform');
    if      u <= 0.92 then do; STATUS = 'Validated';    VALIDATED_BY = 'NV'; QC_BY = 'Programmer2'; end;
    else if u <= 0.98 then do; STATUS = 'In QC Review'; VALIDATED_BY = '';   QC_BY = 'Programmer2'; end;
    else                   do; STATUS = 'Pending';       VALIDATED_BY = '';   QC_BY = '';             end;

    output;
  end;

  drop i idx u;

  label
    TFL_ID       = 'TFL Unique Identifier'
    TYPE         = 'Output Type (Table/Figure/Listing)'
    TITLE        = 'TFL Title'
    PROGRAM      = 'SAS Program Name'
    STATUS       = 'Validation Status'
    VALIDATED_BY = 'Validated By (Initials)'
    QC_BY        = 'QC Programmer'
    DOMAIN       = 'Source ADaM Domain'
    PROTOCOL     = 'Protocol Identifier';
run;

/* TFL status summary */
proc freq data=tfldata.tfl_tracker;
  tables TYPE * STATUS / nocum nopercent;
  title "TFL Tracker — Status by Output Type | Protocol: &protocol";
run;
title;


/*===========================================================================
  SECTION 5 : ENROLLMENT SUMMARY BY ARM AND SITE
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 5.1 : Monthly enrollment by arm
---------------------------------------------------------------------------*/
proc freq data=adam.adsl noprint;
  tables ENROLL_MONTH * ARM / out=enroll_by_month_arm (drop=PERCENT);
run;

proc transpose data=enroll_by_month_arm
               out=enroll_month_wide (rename=(_NAME_=ARM_TYPE))
               prefix=N_;
  by ENROLL_MONTH;
  id ARM;
  var COUNT;
run;

data tfldata.enroll_monthly;
  set enroll_month_wide;
  length MONTH_NAME $5;
  select (ENROLL_MONTH);
    when (1) MONTH_NAME = 'Jan';
    when (2) MONTH_NAME = 'Feb';
    when (3) MONTH_NAME = 'Mar';
    when (4) MONTH_NAME = 'Apr';
    when (5) MONTH_NAME = 'May';
    when (6) MONTH_NAME = 'Jun';
    otherwise MONTH_NAME = 'Unk';
  end;
  TOTAL = sum(of N_:);
  label
    ENROLL_MONTH = 'Enrollment Month Number'
    MONTH_NAME   = 'Enrollment Month Name'
    N_Treatment  = 'Treatment Arm — N Enrolled'
    N_Placebo    = 'Placebo Arm — N Enrolled'
    TOTAL        = 'Total Enrolled';
run;

/*---------------------------------------------------------------------------
  Step 5.2 : Site-level enrollment and disposition summary
---------------------------------------------------------------------------*/
proc sql;
  create table tfldata.site_summary as
  select
    SITE                                          as Site,
    count(USUBJID)                                as Total_Enrolled    label='Total Enrolled',
    sum(ARM='Treatment')                          as N_Treatment       label='Treatment Arm N',
    sum(ARM='Placebo')                            as N_Placebo         label='Placebo Arm N',
    sum(STATUS='Completed')                       as N_Completed       label='Completed N',
    sum(STATUS='Active')                          as N_Active          label='Active N',
    sum(STATUS='Discontinued')                    as N_Discontinued    label='Discontinued N',
    sum(STATUS='Screening Failure')               as N_ScreenFail      label='Screen Failure N',
    round(sum(STATUS='Discontinued') /
          count(USUBJID) * 100, 0.1)              as Dropout_Rate_Pct  label='Dropout Rate (%)'
  from adam.adsl
  group by SITE
  order by Total_Enrolled descending;
quit;

/*---------------------------------------------------------------------------
  Step 5.3 : Print enrollment summary report
---------------------------------------------------------------------------*/
ods listing;
options ls=180;

proc report data=tfldata.site_summary nowd headline headskip
    style(header)=[fontweight=bold];
  column Site Total_Enrolled N_Treatment N_Placebo
         N_Completed N_Active N_Discontinued Dropout_Rate_Pct;
  define Site            / display 'Site'             width=25;
  define Total_Enrolled  / display 'Total\nEnrolled'  width=9  format=3.;
  define N_Treatment     / display 'Treatment\nArm'   width=10 format=3.;
  define N_Placebo       / display 'Placebo\nArm'     width=8  format=3.;
  define N_Completed     / display 'Completed'        width=10 format=3.;
  define N_Active        / display 'Active'           width=8  format=3.;
  define N_Discontinued  / display 'Discontinued'     width=12 format=3.;
  define Dropout_Rate_Pct/ display 'Dropout\nRate (%)' width=10 format=5.1;
  title1 "Protocol: &protocol | Phase &phase";
  title2 "Table: Enrollment Summary by Investigator Site";
  title3 "Data cut-off: &cutoff_dt | Author: &author";
  footnote1 "Source dataset: ADSL | Program: clinical_trial_analytics.sas";
  footnote2 "Dropout Rate = Discontinued / Total Enrolled * 100";
run;
title; footnote;
ods listing close;


/*===========================================================================
  SECTION 6 : AE SUMMARY TABLE BY SOC AND CTCAE GRADE (TFL OUTPUT)
  Mirrors a standard clinical TFL — Table of Adverse Events by
  System Organ Class and CTCAE Grade
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 6.1 : Count AEs by SOC and grade
---------------------------------------------------------------------------*/
proc freq data=adam.adae noprint;
  tables SOC * CTCAE_GRADE / out=ae_by_soc_grade (drop=PERCENT rename=(COUNT=N_AE));
run;

/*---------------------------------------------------------------------------
  Step 6.2 : Transpose grades into columns
---------------------------------------------------------------------------*/
proc transpose data=ae_by_soc_grade
               out=ae_wide (drop=_NAME_ _LABEL_)
               prefix=Grade_;
  by SOC;
  id CTCAE_GRADE;
  var N_AE;
run;

data ae_wide;
  set ae_wide;
  array g{4} Grade_1 Grade_2 Grade_3 Grade_4;
  do k = 1 to 4;
    if missing(g{k}) then g{k} = 0;
  end;
  drop k;

  TOTAL     = Grade_1 + Grade_2 + Grade_3 + Grade_4;
  N_GRADE34 = Grade_3 + Grade_4;   /* Combined Grade 3-4 count */

  if N_GRADE34 > 0 then SAE_FLAG = 'Yes';
  else                   SAE_FLAG = 'No';
run;

proc sort data=ae_wide; by descending TOTAL; run;

/*---------------------------------------------------------------------------
  Step 6.3 : Add subject-incidence counts
             (N subjects with at least one AE in that SOC)
---------------------------------------------------------------------------*/
proc sort data=adam.adae out=adae_dedup nodupkey;
  by USUBJID SOC;
run;

proc freq data=adae_dedup noprint;
  tables SOC / out=soc_subj (rename=(COUNT=N_SUBJ) drop=PERCENT);
run;

proc sql;
  create table tfldata.ae_summary as
  select
    a.SOC,
    b.N_SUBJ                          label='N Subjects with AE',
    a.Grade_1                         label='Grade 1 — Mild',
    a.Grade_2                         label='Grade 2 — Moderate',
    a.Grade_3                         label='Grade 3 — Severe',
    a.Grade_4                         label='Grade 4 — Life-threatening',
    a.TOTAL                           label='Total AEs (All Grades)',
    a.N_GRADE34                       label='Grade 3-4 AEs',
    a.SAE_FLAG                        label='SAE Reported (Y/N)',
    round(a.N_GRADE34 / a.TOTAL * 100, 0.1) as PCT_GRADE34
                                      label='% Grade 3-4'
  from ae_wide   a
  left join soc_subj b on upcase(a.SOC) = upcase(b.SOC)
  order by a.TOTAL descending;
quit;

/*---------------------------------------------------------------------------
  Step 6.4 : Print AE summary table — formatted TFL output
---------------------------------------------------------------------------*/
ods listing;
options ls=200;

proc report data=tfldata.ae_summary nowd headline headskip;
  column SOC N_SUBJ Grade_1 Grade_2 Grade_3 Grade_4 TOTAL N_GRADE34 PCT_GRADE34 SAE_FLAG;

  define SOC         / display 'System Organ Class'     width=40;
  define N_SUBJ      / display 'Subjects\nwith AE (n)'  width=10 format=3.;
  define Grade_1     / display 'Grade 1\n(Mild)'        width=9  format=3.;
  define Grade_2     / display 'Grade 2\n(Moderate)'    width=10 format=3.;
  define Grade_3     / display 'Grade 3\n(Severe)'      width=9  format=3.;
  define Grade_4     / display 'Grade 4\n(Life-Thr.)'   width=10 format=3.;
  define TOTAL       / display 'Total\nAEs'             width=7  format=3.;
  define N_GRADE34   / display 'Grade\n3-4 (n)'         width=9  format=3.;
  define PCT_GRADE34 / display '% Grade\n3-4'           width=9  format=5.1;
  define SAE_FLAG    / display 'SAE\nFlag'              width=6;

  title1 "Protocol: &protocol | Phase &phase";
  title2 "Table: Adverse Events by System Organ Class and CTCAE Grade";
  title3 "Safety Population (SAFFL=Y) | CTCAE Version 5.0";
  title4 "Data cut-off: &cutoff_dt | Author: &author";
  footnote1 "Source datasets: ADAE, ADSL | Program: clinical_trial_analytics.sas";
  footnote2 "AEs sorted by total count descending.";
  footnote3 "SAE Flag = Yes if any Grade 3 or Grade 4 AE reported in that SOC.";
  footnote4 "Grade 3 = Severe; Grade 4 = Life-threatening per CTCAE v5.0.";
run;
title; footnote;
ods listing close;


/*===========================================================================
  SECTION 7 : VALIDATION CHECKS
===========================================================================*/

/* Check: ADSL subject count matches target sample size */
proc sql noprint;
  select count(*) into :n_adsl from adam.adsl;
quit;
%put NOTE: ADSL subject count = &n_adsl (expected 200);

/* Check: No duplicate USUBJIDs in ADSL */
proc sort data=adam.adsl nodupkey out=_null_ dupout=_dups_;
  by USUBJID;
run;
%let dup_count = 0;
proc sql noprint; select count(*) into :dup_count from _dups_; quit;
%if &dup_count > 0 %then
  %put ERROR: &dup_count duplicate USUBJIDs found in ADSL.;
%else
  %put NOTE: ADSL — No duplicate USUBJIDs. Check passed.;

/* Check: All ADAE USUBJIDs exist in ADSL */
proc sql;
  select count(*) as Orphan_AEs
  from adam.adae a
  where a.USUBJID not in (select USUBJID from adam.adsl);
quit;

/* Check: AE grade values are 1–4 only */
proc freq data=adam.adae;
  tables CTCAE_GRADE / nocum nopercent;
  title "ADAE — CTCAE Grade validation (expect values 1-4 only)";
run;
title;

/* Check: TFL total count */
proc sql noprint;
  select count(*) into :n_tfl from tfldata.tfl_tracker;
quit;
%put NOTE: TFL Tracker total records = &n_tfl (expected 172);

/* Summary of all output datasets */
%macro ds_summary(lib=, ds=);
  proc contents data=&lib..&ds noprint out=_cont_ (keep=NOBS NVAR); run;
  proc sql noprint;
    select NOBS, NVAR into :nobs, :nvar from _cont_;
  quit;
  %put NOTE: &lib..&ds — Observations=&nobs | Variables=&nvar;
%mend ds_summary;

%ds_summary(lib=adam,    ds=adsl);
%ds_summary(lib=adam,    ds=adae);
%ds_summary(lib=tfldata, ds=tfl_tracker);
%ds_summary(lib=tfldata, ds=ae_summary);
%ds_summary(lib=tfldata, ds=site_summary);
%ds_summary(lib=tfldata, ds=enroll_monthly);

%put NOTE: ============================================================;
%put NOTE: All programs complete. Protocol: &protocol;
%put NOTE: Output datasets: ADSL, ADAE, TFL_Tracker, AE_Summary,;
%put NOTE:                  Site_Summary, Enroll_Monthly;
%put NOTE: ============================================================;
