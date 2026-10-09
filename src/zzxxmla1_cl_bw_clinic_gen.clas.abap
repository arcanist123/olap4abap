*----------------------------------------------------------------------------------------------------------------------*
* olap4abap - XMLA server with an MDX engine for SAP BW               https://github.com/arcanist123/olap4abap
* Copyright (c) 2026 the olap4abap authors
*
* This program and the accompanying materials are made available under the terms of the Eclipse Public License 2.0,
* which is available at https://www.eclipse.org/legal/epl-2.0/
* SPDX-License-Identifier: EPL-2.0
*
* olap4abap contains code derived from Mondrian (Eclipse Public License 1.0): Copyright (C) 1998-2005 Julian Hyde,
* Copyright (C) 2005-2021 Hitachi Vantara and others, Copyright (C) 2021-2025 Sergei Semenkov. See the NOTICE file.
*----------------------------------------------------------------------------------------------------------------------*
"! The clinic demo (docs/clinic-demo.md): visits of patients to a clinic in 2024 and 2025, made up by this class, so the
"! demo carries no third-party data. It creates InfoArea ZCLINIC with
"! - the InfoCube ZCLVISIT (characteristics patient, physician, diagnosis, visit type and date with flat attributes),
"! - on the physician ZCLDOC, which is authorization relevant, the hierarchy ZCLDOC_ORG (clinic > division > department >
"!   physician): version dependent, the entire hierarchy time dependent, two versions with two time slices each,
"! - the cube-type aDSO ZCLVISITA with the same visits and BW's standard time characteristics in place of the date,
"! loads both, generates the CDS views of the characteristics (ZZXXMLA1_CL_BW_VIEW_GEN), writes a schema per provider
"! (/WEB-INF/schema/ZCLVISIT.xml, /WEB-INF/schema/ZCLVISITA.xml) and adds a catalog for each to
"! /WEB-INF/datasources.xml.
"! The data comes from a seeded pseudo-random generator: every run gives the same visits. BW's blank member (the initial
"! key, SID 0) exists in every hierarchy; a few visits use it (no diagnosis recorded yet, no physician assigned at
"! triage, a patient not identified, no visit type), so it has data.
"! An upper bound on the visits thins them evenly over the two years, for a smaller demo (a test system).
"! Every run deletes the aDSO, the cube, the views and the InfoObjects listed here and creates them again: never point it
"! at objects that hold data you want to keep. Run with program ZZXXMLA1_SETUP or sapcli class execute.
CLASS zzxxmla1_cl_bw_clinic_gen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_infoarea TYPE rsinfoarea VALUE 'ZCLINIC'.
    CONSTANTS c_cube     TYPE rsinfocube VALUE 'ZCLVISIT'.
    CONSTANTS c_adso     TYPE rsoadsonm VALUE 'ZCLVISITA'.
    CONSTANTS c_hierarchy TYPE rshienm VALUE 'ZCLDOC_ORG'.

    "! Generates everything; the log of the run.
    "! @parameter max_visits | at most this many visits, spread evenly over the days; 0: all of them
    METHODS run
      IMPORTING max_visits    TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_first_day TYPE d VALUE '20240101'.
    CONSTANTS c_last_day  TYPE d VALUE '20251231'.
    CONSTANTS c_seed      TYPE int8 VALUE 20240101.
    CONSTANTS c_patients  TYPE i VALUE 2000.
    CONSTANTS c_lab_price TYPE p LENGTH 8 DECIMALS 2 VALUE '24.50'.
    CONSTANTS c_minute_price TYPE p LENGTH 8 DECIMALS 2 VALUE '1.20'.

    TYPES ty_t_iobjnm TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_cha,
        name       TYPE rsiobjnm,
        text       TYPE rstxtlg,
        datatp     TYPE datatype_d,
        leng       TYPE i,
        attributes TYPE ty_t_iobjnm,
        "! with hierarchies: version dependent, the entire hierarchy time dependent
        hierarchies   TYPE abap_bool,
        auth_relevant TYPE abap_bool,
      END OF ty_cha,
      ty_t_cha TYPE STANDARD TABLE OF ty_cha WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_kyf,
        name TYPE rsiobjnm,
        text TYPE rstxtlg,
      END OF ty_kyf,
      ty_t_kyf TYPE STANDARD TABLE OF ty_kyf WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_dime,
        suffix  TYPE c LENGTH 1,
        text    TYPE rstxtlg,
        iobjtp  TYPE rsiobjtp,
        iobjnms TYPE ty_t_iobjnm,
      END OF ty_dime,
      ty_t_dime TYPE STANDARD TABLE OF ty_dime WITH EMPTY KEY.
    TYPES ty_t_row TYPE STANDARD TABLE OF string_table WITH EMPTY KEY.
    TYPES:
      "! the master data of a characteristic: per row the key and the values of the attributes, in their order
      BEGIN OF ty_md,
        iobjnm     TYPE rsiobjnm,
        attributes TYPE ty_t_iobjnm,
        rows       TYPE ty_t_row,
      END OF ty_md,
      ty_t_md TYPE STANDARD TABLE OF ty_md WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_weight,
        key    TYPE string,
        weight TYPE i,
      END OF ty_weight,
      ty_t_weight TYPE STANDARD TABLE OF ty_weight WITH EMPTY KEY.
    TYPES:
      "! a weight that applies within a group (the departments of an age group, the diagnoses of a department)
      BEGIN OF ty_group_weight,
        scope  TYPE string,
        key    TYPE string,
        weight TYPE i,
      END OF ty_group_weight,
      ty_t_group_weight TYPE STANDARD TABLE OF ty_group_weight WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_patient,
        id         TYPE i,
        name       TYPE string,
        sex        TYPE string,
        birth_year TYPE i,
        age_group  TYPE string,
        blood      TYPE string,
        insurance  TYPE string,
        city       TYPE string,
        region     TYPE string,
      END OF ty_patient,
      ty_t_patient TYPE STANDARD TABLE OF ty_patient WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_physician,
        id         TYPE i,
        name       TYPE string,
        department TYPE string,
        years      TYPE i,
      END OF ty_physician,
      ty_t_physician TYPE STANDARD TABLE OF ty_physician WITH EMPTY KEY.
    TYPES:
      "! a node of a hierarchy of the physicians: a text node (with a text) or a physician (its key, no text)
      BEGIN OF ty_hie_node,
        name   TYPE string,
        parent TYPE string,
        text   TYPE string,
      END OF ty_hie_node,
      ty_t_hie_node TYPE STANDARD TABLE OF ty_hie_node WITH EMPTY KEY.
    TYPES:
      "! a physician in another department than in the master data
      BEGIN OF ty_move,
        physician  TYPE i,
        department TYPE string,
      END OF ty_move,
      ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY.
    TYPES:
      "! a time slice of a version of the hierarchy ZCLDOC_ORG
      BEGIN OF ty_hierarchy,
        version  TYPE rsversion,
        datefrom TYPE d,
        dateto   TYPE d,
        text     TYPE string,
        nodes    TYPE ty_t_hie_node,
      END OF ty_hierarchy,
      ty_t_hierarchy TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    TYPES ty_t_htab TYPE rsndi_t_htabstr.
    TYPES ty_t_ndi_message TYPE rsndi_t_message.
    TYPES:
      BEGIN OF ty_diagnosis,
        code    TYPE string,
        name    TYPE string,
        diagnosis_group TYPE string,
        chapter         TYPE string,
      END OF ty_diagnosis,
      ty_t_diagnosis TYPE STANDARD TABLE OF ty_diagnosis WITH EMPTY KEY.
    TYPES:
      "! one visit; a key of 0 or blank is BW's blank member
      BEGIN OF ty_visit,
        patient    TYPE i,
        physician  TYPE i,
        diagnosis  TYPE string,
        visit_type TYPE string,
        day        TYPE d,
        duration   TYPE i,
        wait       TYPE i,
        labs       TYPE i,
        charges    TYPE p LENGTH 8 DECIMALS 2,
      END OF ty_visit,
      ty_t_visit TYPE STANDARD TABLE OF ty_visit WITH EMPTY KEY.
    TYPES:
      "! BW's time characteristics of a day
      BEGIN OF ty_calendar,
        calday     TYPE d,
        calweek    TYPE n LENGTH 6,
        calmonth   TYPE n LENGTH 6,
        calquarter TYPE n LENGTH 5,
        calyear    TYPE n LENGTH 4,
      END OF ty_calendar.

    DATA log TYPE string_table.
    DATA seed TYPE int8.
    DATA patients TYPE ty_t_patient.
    DATA physicians TYPE ty_t_physician.
    DATA diagnoses TYPE ty_t_diagnosis.
    DATA visits TYPE ty_t_visit.

    METHODS write IMPORTING text TYPE csequence.
    METHODS characteristics RETURNING VALUE(result) TYPE ty_t_cha.
    METHODS key_figures RETURNING VALUE(result) TYPE ty_t_kyf.
    METHODS dimensions RETURNING VALUE(result) TYPE ty_t_dime.
    METHODS all_iobjnm RETURNING VALUE(result) TYPE ty_t_iobjnm.
    "! The characteristics that are dimensions of the cube (and have a view).
    METHODS dimension_characteristics RETURNING VALUE(result) TYPE ty_t_iobjnm.

    "! The next pseudo-random number from 1 to n (Park and Miller's minimal standard generator).
    METHODS random IMPORTING n TYPE i RETURNING VALUE(result) TYPE i.
    "! A key chosen with the probability of its weight.
    METHODS pick IMPORTING weights TYPE ty_t_weight RETURNING VALUE(result) TYPE string.
    METHODS build_patients.
    METHODS build_physicians.
    METHODS build_diagnoses.
    "! The time slices of the versions of ZCLDOC_ORG.
    METHODS hierarchies RETURNING VALUE(result) TYPE ty_t_hierarchy.
    "! The nodes of a time slice: the text nodes and below its department every physician, moved ones elsewhere.
    METHODS organization
      IMPORTING text_nodes    TYPE ty_t_hie_node
                moves         TYPE ty_t_move OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! Appends a node and its subtree to the hierarchy table (NDI format: parent, first child and next sibling).
    METHODS add_node
      IMPORTING nodes    TYPE ty_t_hie_node
                node     TYPE ty_hie_node
                parentid TYPE rshienodid
                tlevel   TYPE i
      CHANGING  htab     TYPE ty_t_htab.
    "! The departments a patient of each age group is sent to, with their weights.
    METHODS department_weights RETURNING VALUE(result) TYPE ty_t_group_weight.
    "! The diagnoses each department sees, with their weights.
    METHODS diagnosis_weights RETURNING VALUE(result) TYPE ty_t_group_weight.
    METHODS build_visits.
    "! Keeps max_visits of the visits, evenly spread, in their order.
    METHODS limit_visits IMPORTING max_visits TYPE i.
    METHODS master_data RETURNING VALUE(result) TYPE ty_t_md.
    METHODS calendar IMPORTING day TYPE d RETURNING VALUE(result) TYPE ty_calendar.

    METHODS delete_all.
    METHODS delete_cube.
    METHODS delete_adso.
    METHODS delete_views.
    METHODS delete_hierarchies.
    METHODS delete_infoobjects.
    METHODS ensure_infoarea.
    METHODS create_characteristic IMPORTING cha TYPE ty_cha.
    METHODS create_key_figure IMPORTING kyf TYPE ty_kyf.
    METHODS activate_infoobjects.
    METHODS create_cube.
    METHODS activate_cube.
    METHODS load_master_data IMPORTING md TYPE ty_md.
    "! Saves and activates a time slice of ZCLDOC_ORG (RSNDI_SHIE_STRUCTURE_UPDATE4, RSNDI_SHIE_ACTIVATE; UPDATE3
    "! dumps on the 2025 system: CL_RSSH_HIERARCHY_FUNC=>NDI_UPDATE no longer takes its table of hierarchy texts).
    METHODS load_hierarchy IMPORTING hierarchy TYPE ty_hierarchy.
    METHODS load_cube.
    "! Generates the views of the cube's characteristics and of the aDSO's time characteristics.
    METHODS generate_views RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view.
    METHODS create_adso.
    "! The name BW generated for a table or view of the aDSO (CL_RSO_ADSO=>GET_TABLNM).
    METHODS adso_table IMPORTING type TYPE rsdsotabtype RETURNING VALUE(result) TYPE tabname.
    METHODS load_adso.
    "! Counts the rows of a fact table or view and sums the duration.
    METHODS verify IMPORTING source TYPE csequence.

    "! The schema of the cube (adso = false) or of the aDSO.
    METHODS schema_xml
      IMPORTING adso          TYPE abap_bool
                views         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
      RETURNING VALUE(result) TYPE string.
    "! The key attribute's columns: on the cube keyed by the SID and named by the value, on the aDSO keyed by the value.
    METHODS key_columns
      IMPORTING adso          TYPE abap_bool
                column        TYPE csequence
                data_type     TYPE csequence
      RETURNING VALUE(result) TYPE string.
    METHODS attribute_xml
      IMPORTING name          TYPE csequence
                column        TYPE csequence
                data_type     TYPE csequence DEFAULT `String`
                level_type    TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE string.
    METHODS view_of
      IMPORTING views         TYPE zzxxmla1_cl_bw_view_gen=>ty_t_view
                iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE string.
    "! Writes the schema file and adds its catalog to the data sources file if it is not there.
    METHODS write_catalog
      IMPORTING catalog TYPE csequence
                xml     TYPE string.

    "! The field of an InfoObject in BW's generated tables (RSD_FIELDNM_GET_FROM_IOBJNM), checked against the structure.
    METHODS iobj_field
      IMPORTING struct        TYPE REF TO cl_abap_structdescr
                iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE string.
    METHODS write_return IMPORTING return TYPE bapiret2_t.
    METHODS write_exception IMPORTING error TYPE REF TO cx_root.
    METHODS write_messages IMPORTING messages TYPE rs_t_msg.
    METHODS write_ndi_messages IMPORTING messages TYPE ty_t_ndi_message.
ENDCLASS.



CLASS zzxxmla1_cl_bw_clinic_gen IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    LOOP AT run( ) INTO DATA(line).
      out->write( line ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run.
    CLEAR log.
    seed = c_seed.
    build_patients( ).
    build_physicians( ).
    build_diagnoses( ).
    build_visits( ).
    limit_visits( max_visits ).
    write( |{ lines( patients ) } patients, { lines( physicians ) } physicians, { lines( diagnoses ) } diagnoses, | &&
           |{ lines( visits ) } visits| ).

    delete_all( ).
    ensure_infoarea( ).
    LOOP AT characteristics( ) INTO DATA(cha).
      create_characteristic( cha ).
    ENDLOOP.
    LOOP AT key_figures( ) INTO DATA(kyf).
      create_key_figure( kyf ).
    ENDLOOP.
    activate_infoobjects( ).
    create_cube( ).
    activate_cube( ).
    LOOP AT master_data( ) INTO DATA(md).
      load_master_data( md ).
    ENDLOOP.
    LOOP AT hierarchies( ) INTO DATA(hierarchy).
      load_hierarchy( hierarchy ).
    ENDLOOP.
    load_cube( ).
    verify( |/BIC/F{ c_cube }| ).
    create_adso( ).
    load_adso( ).
    verify( adso_table( cl_rsdso_constants=>n_c_viewtype_reporting ) ).

    DATA(views) = generate_views( ).
    write_catalog( catalog = c_cube xml = schema_xml( adso = abap_false views = views ) ).
    write_catalog( catalog = c_adso xml = schema_xml( adso = abap_true views = views ) ).
    result = log.
  ENDMETHOD.

  METHOD write.
    APPEND text TO log.
  ENDMETHOD.

  METHOD characteristics.
    " attributes first: the dimension characteristics reference them; NUMC attributes are delivered as numbers
    result = VALUE #(
      ( name = 'ZCLPNAME' text = 'Patient Name'      leng = 60 )
      ( name = 'ZCLSEX'   text = 'Sex'               leng = 10 )
      ( name = 'ZCLBYEAR' text = 'Birth Year'        datatp = 'NUMC' leng = 4 )
      ( name = 'ZCLAGEGR' text = 'Age Group'         leng = 10 )
      ( name = 'ZCLBLOOD' text = 'Blood Group'       leng = 3 )
      ( name = 'ZCLINSUR' text = 'Insurance'         leng = 20 )
      ( name = 'ZCLCITY'  text = 'City'              leng = 40 )
      ( name = 'ZCLREGIO' text = 'Region'            leng = 40 )
      ( name = 'ZCLDNAME' text = 'Physician Name'    leng = 60 )
      ( name = 'ZCLDEPT'  text = 'Department'        leng = 40 )
      ( name = 'ZCLEXPER' text = 'Years in Practice' datatp = 'NUMC' leng = 2 )
      ( name = 'ZCLDTEXT' text = 'Diagnosis Name'    leng = 60 )
      ( name = 'ZCLDGRP'  text = 'Diagnosis Group'   leng = 60 )
      ( name = 'ZCLDCHAP' text = 'Diagnosis Chapter' leng = 60 )
      ( name = 'ZCLSETNG' text = 'Care Setting'      leng = 20 )
      ( name = 'ZCLTHEDT' text = 'The Date'          leng = 10 )
      ( name = 'ZCLDAYNM' text = 'Day Name'          leng = 10 )
      ( name = 'ZCLMONNM' text = 'Month Name'        leng = 10 )
      ( name = 'ZCLYEAR'  text = 'Year'              datatp = 'NUMC' leng = 4 )
      ( name = 'ZCLQTR'   text = 'Quarter'           leng = 2 )
      ( name = 'ZCLMONTH' text = 'Month of Year'     datatp = 'NUMC' leng = 2 )
      ( name = 'ZCLWEEK'  text = 'Week of Year'      datatp = 'NUMC' leng = 2 )
      ( name = 'ZCLDAYOM' text = 'Day of Month'      datatp = 'NUMC' leng = 2 )
      " the dimension characteristics
      ( name = 'ZCLPAT'   text = 'Patient'    datatp = 'NUMC' leng = 6
        attributes = VALUE #( ( 'ZCLPNAME' ) ( 'ZCLSEX' ) ( 'ZCLBYEAR' ) ( 'ZCLAGEGR' ) ( 'ZCLBLOOD' ) ( 'ZCLINSUR' )
                              ( 'ZCLCITY' ) ( 'ZCLREGIO' ) ) )
      ( name = 'ZCLDOC'   text = 'Physician'  datatp = 'NUMC' leng = 3
        attributes = VALUE #( ( 'ZCLDNAME' ) ( 'ZCLDEPT' ) ( 'ZCLEXPER' ) )
        hierarchies = abap_true auth_relevant = abap_true )
      ( name = 'ZCLDIAG'  text = 'Diagnosis'  leng = 5
        attributes = VALUE #( ( 'ZCLDTEXT' ) ( 'ZCLDGRP' ) ( 'ZCLDCHAP' ) ) )
      ( name = 'ZCLVTYPE' text = 'Visit Type' leng = 20
        attributes = VALUE #( ( 'ZCLSETNG' ) ) )
      " the day as YYYYMMDD; a plain characteristic, not a BW time characteristic, so it can have attributes
      ( name = 'ZCLDATE'  text = 'Date'       datatp = 'NUMC' leng = 8
        attributes = VALUE #( ( 'ZCLTHEDT' ) ( 'ZCLDAYNM' ) ( 'ZCLMONNM' ) ( 'ZCLYEAR' ) ( 'ZCLQTR' ) ( 'ZCLMONTH' )
                              ( 'ZCLWEEK' ) ( 'ZCLDAYOM' ) ) ) ).
  ENDMETHOD.

  METHOD key_figures.
    result = VALUE #(
      " 1 per visit: the aDSO adds up visits with the same keys, so a count of rows would not be the visits
      ( name = 'ZCLVISNO' text = 'Visits' )
      ( name = 'ZCLDUR'  text = 'Duration (min)' )
      ( name = 'ZCLWAIT' text = 'Waiting Time (min)' )
      ( name = 'ZCLLABS' text = 'Lab Tests' )
      ( name = 'ZCLCHRG' text = 'Charges' ) ).
  ENDMETHOD.

  METHOD dimensions.
    result = VALUE #(
      ( suffix = 'P' text = 'Data Package' iobjtp = 'DPA'
        iobjnms = VALUE #( ( '0CHNGID' ) ( '0RECORDTP' ) ( '0REQUID' ) ) )
      ( suffix = '1' text = 'Patient'    iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLPAT' ) ) )
      ( suffix = '2' text = 'Physician'  iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLDOC' ) ) )
      ( suffix = '3' text = 'Diagnosis'  iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLDIAG' ) ) )
      ( suffix = '4' text = 'Visit Type' iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLVTYPE' ) ) )
      ( suffix = '5' text = 'Time'       iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLDATE' ) ) ) ).
  ENDMETHOD.

  METHOD all_iobjnm.
    result = VALUE #( FOR c IN characteristics( ) ( c-name ) ).
    APPEND LINES OF VALUE ty_t_iobjnm( FOR k IN key_figures( ) ( k-name ) ) TO result.
  ENDMETHOD.

  METHOD dimension_characteristics.
    result = VALUE #( ( 'ZCLPAT' ) ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ( 'ZCLVTYPE' ) ( 'ZCLDATE' ) ).
  ENDMETHOD.

  METHOD random.
    seed = ( seed * 48271 ) MOD 2147483647.
    result = seed MOD n + 1.
  ENDMETHOD.

  METHOD pick.
    DATA(total) = 0.
    LOOP AT weights INTO DATA(weight).
      total = total + weight-weight.
    ENDLOOP.
    DATA(chosen) = random( total ).
    LOOP AT weights INTO weight.
      chosen = chosen - weight-weight.
      IF chosen <= 0.
        result = weight-key.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_patients.
    DATA(female) = VALUE string_table( ( `Anna` ) ( `Maria` ) ( `Laura` ) ( `Sofia` ) ( `Emma` ) ( `Julia` )
                                       ( `Clara` ) ( `Elena` ) ( `Hannah` ) ( `Lea` ) ( `Mia` ) ( `Nora` ) ).
    DATA(male) = VALUE string_table( ( `Lukas` ) ( `David` ) ( `Jonas` ) ( `Felix` ) ( `Paul` ) ( `Daniel` )
                                     ( `Simon` ) ( `Tobias` ) ( `Adam` ) ( `Erik` ) ( `Leon` ) ( `Martin` ) ).
    DATA(family) = VALUE string_table( ( `Adler` ) ( `Bauer` ) ( `Berger` ) ( `Brandt` ) ( `Engel` ) ( `Fischer` )
                                       ( `Frank` ) ( `Hahn` ) ( `Horn` ) ( `Keller` ) ( `Klein` ) ( `Koch` )
                                       ( `Lang` ) ( `Lorenz` ) ( `Meier` ) ( `Novak` ) ( `Roth` ) ( `Sommer` )
                                       ( `Vogel` ) ( `Wolf` ) ).
    " region > city, two cities per region
    DATA(cities) = VALUE ty_t_group_weight(
      ( scope = `North`   key = `Ashford` )   ( scope = `North`   key = `Brightwater` )
      ( scope = `South`   key = `Copperton` ) ( scope = `South`   key = `Dunmore` )
      ( scope = `East`    key = `Eastbrook` ) ( scope = `East`    key = `Fairhaven` )
      ( scope = `West`    key = `Glenwood` )  ( scope = `West`    key = `Harrowgate` )
      ( scope = `Central` key = `Ironbridge` ) ( scope = `Central` key = `Juniper Hills` ) ).
    DATA(age_groups) = VALUE ty_t_weight( ( key = `0-17` weight = 20 ) ( key = `18-39` weight = 27 )
                                          ( key = `40-64` weight = 30 ) ( key = `65+` weight = 23 ) ).
    DATA(blood_groups) = VALUE ty_t_weight( ( key = `O+` weight = 37 ) ( key = `A+` weight = 34 )
                                            ( key = `B+` weight = 9 ) ( key = `AB+` weight = 4 )
                                            ( key = `O-` weight = 7 ) ( key = `A-` weight = 6 )
                                            ( key = `B-` weight = 2 ) ( key = `AB-` weight = 1 ) ).
    DATA(insurances) = VALUE ty_t_weight( ( key = `Statutory` weight = 75 ) ( key = `Private` weight = 20 )
                                          ( key = `Self-pay` weight = 5 ) ).
    CLEAR patients.
    DO c_patients TIMES.
      DATA(patient) = VALUE ty_patient( id = sy-index ).
      patient-sex = COND #( WHEN random( 2 ) = 1 THEN `Female` ELSE `Male` ).
      DATA(first) = COND string( WHEN patient-sex = `Female` THEN female[ random( lines( female ) ) ]
                                 ELSE male[ random( lines( male ) ) ] ).
      patient-name = |{ family[ random( lines( family ) ) ] }, { first }|.
      " the age on 1 January 2024
      patient-age_group = pick( age_groups ).
      DATA(age) = SWITCH i( patient-age_group WHEN `0-17`  THEN random( 18 ) - 1
                                              WHEN `18-39` THEN 17 + random( 22 )
                                              WHEN `40-64` THEN 39 + random( 25 )
                                              ELSE 64 + random( 30 ) ).
      patient-birth_year = 2023 - age.
      patient-blood = pick( blood_groups ).
      patient-insurance = pick( insurances ).
      DATA(city) = cities[ random( lines( cities ) ) ].
      patient-city = city-key.
      patient-region = city-scope.
      APPEND patient TO patients.
    ENDDO.
  ENDMETHOD.

  METHOD build_physicians.
    physicians = VALUE #(
      ( id = 1  name = `Dr. Amelia Hart`     department = `General Practice`   years = 22 )
      ( id = 2  name = `Dr. Ben Okafor`      department = `General Practice`   years = 9 )
      ( id = 3  name = `Dr. Chiara Russo`    department = `General Practice`   years = 15 )
      ( id = 4  name = `Dr. Daniel Weiss`    department = `General Practice`   years = 4 )
      ( id = 5  name = `Dr. Eva Lindqvist`   department = `General Practice`   years = 28 )
      ( id = 6  name = `Dr. Farah Haddad`    department = `Pediatrics`         years = 12 )
      ( id = 7  name = `Dr. George Mills`    department = `Pediatrics`         years = 19 )
      ( id = 8  name = `Dr. Hana Sato`       department = `Pediatrics`         years = 6 )
      ( id = 9  name = `Dr. Ivan Petrov`     department = `Cardiology`         years = 25 )
      ( id = 10 name = `Dr. Julia Brandt`    department = `Cardiology`         years = 14 )
      ( id = 11 name = `Dr. Karim Aziz`      department = `Cardiology`         years = 8 )
      ( id = 12 name = `Dr. Lena Fischer`    department = `Pulmonology`        years = 17 )
      ( id = 13 name = `Dr. Marco Bianchi`   department = `Pulmonology`        years = 11 )
      ( id = 14 name = `Dr. Nina Kowalski`   department = `Orthopedics`        years = 20 )
      ( id = 15 name = `Dr. Oscar Nilsson`   department = `Orthopedics`        years = 7 )
      ( id = 16 name = `Dr. Priya Raman`     department = `Orthopedics`        years = 13 )
      ( id = 17 name = `Dr. Quentin Moreau`  department = `Dermatology`        years = 16 )
      ( id = 18 name = `Dr. Rosa Delgado`    department = `Dermatology`        years = 5 )
      ( id = 19 name = `Dr. Samuel Osei`     department = `Emergency Medicine` years = 10 )
      ( id = 20 name = `Dr. Tara Quinn`      department = `Emergency Medicine` years = 3 ) ).
  ENDMETHOD.

  METHOD build_diagnoses.
    " codes of ICD-10 with names in plain words; the group Influenza has a single diagnosis
    diagnoses = VALUE #(
      ( code = `J06` name = `Upper respiratory infection`
        diagnosis_group = `Upper respiratory infections` chapter = `Respiratory` )
      ( code = `J02` name = `Sore throat`
        diagnosis_group = `Upper respiratory infections` chapter = `Respiratory` )
      ( code = `J01` name = `Sinusitis`
        diagnosis_group = `Upper respiratory infections` chapter = `Respiratory` )
      ( code = `J11` name = `Influenza`
        diagnosis_group = `Influenza` chapter = `Respiratory` )
      ( code = `J20` name = `Acute bronchitis`
        diagnosis_group = `Lower respiratory diseases` chapter = `Respiratory` )
      ( code = `J18` name = `Pneumonia`
        diagnosis_group = `Lower respiratory diseases` chapter = `Respiratory` )
      ( code = `J45` name = `Asthma`
        diagnosis_group = `Chronic lower respiratory diseases` chapter = `Respiratory` )
      ( code = `J44` name = `COPD`
        diagnosis_group = `Chronic lower respiratory diseases` chapter = `Respiratory` )
      ( code = `I10` name = `Hypertension`
        diagnosis_group = `Hypertensive diseases` chapter = `Circulatory` )
      ( code = `I20` name = `Angina`
        diagnosis_group = `Ischaemic heart diseases` chapter = `Circulatory` )
      ( code = `I25` name = `Chronic ischaemic heart disease`
        diagnosis_group = `Ischaemic heart diseases` chapter = `Circulatory` )
      ( code = `I48` name = `Atrial fibrillation`
        diagnosis_group = `Other heart diseases` chapter = `Circulatory` )
      ( code = `I50` name = `Heart failure`
        diagnosis_group = `Other heart diseases` chapter = `Circulatory` )
      ( code = `E11` name = `Type 2 diabetes`
        diagnosis_group = `Diabetes` chapter = `Endocrine and metabolic` )
      ( code = `E78` name = `Lipid disorder`
        diagnosis_group = `Metabolic disorders` chapter = `Endocrine and metabolic` )
      ( code = `E03` name = `Hypothyroidism`
        diagnosis_group = `Thyroid disorders` chapter = `Endocrine and metabolic` )
      ( code = `M54` name = `Back pain`
        diagnosis_group = `Back problems` chapter = `Musculoskeletal` )
      ( code = `M17` name = `Knee osteoarthritis`
        diagnosis_group = `Joint disorders` chapter = `Musculoskeletal` )
      ( code = `M25` name = `Joint pain`
        diagnosis_group = `Joint disorders` chapter = `Musculoskeletal` )
      ( code = `M75` name = `Shoulder disorder`
        diagnosis_group = `Soft tissue disorders` chapter = `Musculoskeletal` )
      ( code = `L20` name = `Atopic dermatitis`
        diagnosis_group = `Dermatitis` chapter = `Skin` )
      ( code = `L30` name = `Other dermatitis`
        diagnosis_group = `Dermatitis` chapter = `Skin` )
      ( code = `L70` name = `Acne`
        diagnosis_group = `Other skin diseases` chapter = `Skin` )
      ( code = `L40` name = `Psoriasis`
        diagnosis_group = `Other skin diseases` chapter = `Skin` )
      ( code = `A09` name = `Gastroenteritis`
        diagnosis_group = `Intestinal infections` chapter = `Infections` )
      ( code = `B34` name = `Viral infection`
        diagnosis_group = `Viral infections` chapter = `Infections` )
      ( code = `B01` name = `Chickenpox`
        diagnosis_group = `Viral infections` chapter = `Infections` )
      ( code = `S93` name = `Ankle sprain`
        diagnosis_group = `Injuries of limbs` chapter = `Injuries` )
      ( code = `S52` name = `Forearm fracture`
        diagnosis_group = `Injuries of limbs` chapter = `Injuries` )
      ( code = `S61` name = `Hand wound`
        diagnosis_group = `Injuries of limbs` chapter = `Injuries` )
      ( code = `S06` name = `Concussion`
        diagnosis_group = `Head injuries` chapter = `Injuries` )
      ( code = `F32` name = `Depression`
        diagnosis_group = `Mood disorders` chapter = `Mental health` )
      ( code = `F41` name = `Anxiety disorder`
        diagnosis_group = `Anxiety disorders` chapter = `Mental health` )
      ( code = `Z00` name = `General check-up`
        diagnosis_group = `Examinations` chapter = `Check-ups` )
      ( code = `Z23` name = `Vaccination`
        diagnosis_group = `Examinations` chapter = `Check-ups` )
      ( code = `Z09` name = `Follow-up examination`
        diagnosis_group = `Follow-up care` chapter = `Check-ups` ) ).
  ENDMETHOD.

  METHOD hierarchies.
    " 2024: three divisions. On 1 January 2025 the actual organization (version 001) gets a division Internal Medicine
    " for cardiology and pulmonology, dermatology moves to primary care and two physicians change their department (the
    " attribute Department keeps the old one); the plan (version 002) kept the departments and put emergency medicine
    " into primary care instead.
    DATA(slice_2024) = organization( VALUE #(
      ( name = `CLINIC` text = `Clinic` )
      ( name = `PRIMARY`   parent = `CLINIC`    text = `Primary Care` )
      ( name = `SPECIAL`   parent = `CLINIC`    text = `Specialist Care` )
      ( name = `EMERGENCY` parent = `CLINIC`    text = `Emergency Care` )
      ( name = `GP`        parent = `PRIMARY`   text = `General Practice` )
      ( name = `PED`       parent = `PRIMARY`   text = `Pediatrics` )
      ( name = `CARD`      parent = `SPECIAL`   text = `Cardiology` )
      ( name = `PULM`      parent = `SPECIAL`   text = `Pulmonology` )
      ( name = `ORTH`      parent = `SPECIAL`   text = `Orthopedics` )
      ( name = `DERM`      parent = `SPECIAL`   text = `Dermatology` )
      ( name = `EMER`      parent = `EMERGENCY` text = `Emergency Medicine` ) ) ).
    DATA(actual_2025) = organization(
      text_nodes = VALUE #(
        ( name = `CLINIC` text = `Clinic` )
        ( name = `PRIMARY`   parent = `CLINIC`    text = `Primary Care` )
        ( name = `SPECIAL`   parent = `CLINIC`    text = `Specialist Care` )
        ( name = `EMERGENCY` parent = `CLINIC`    text = `Emergency Care` )
        ( name = `GP`        parent = `PRIMARY`   text = `General Practice` )
        ( name = `PED`       parent = `PRIMARY`   text = `Pediatrics` )
        ( name = `DERM`      parent = `PRIMARY`   text = `Dermatology` )
        ( name = `INTMED`    parent = `SPECIAL`   text = `Internal Medicine` )
        ( name = `CARD`      parent = `INTMED`    text = `Cardiology` )
        ( name = `PULM`      parent = `INTMED`    text = `Pulmonology` )
        ( name = `ORTH`      parent = `SPECIAL`   text = `Orthopedics` )
        ( name = `EMER`      parent = `EMERGENCY` text = `Emergency Medicine` ) )
      " Dr. Hana Sato to general practice, Dr. Karim Aziz to emergency medicine
      moves = VALUE #( ( physician = 8 department = `GP` ) ( physician = 11 department = `EMER` ) ) ).
    DATA(plan_2025) = organization( VALUE #(
      ( name = `CLINIC` text = `Clinic` )
      ( name = `PRIMARY`   parent = `CLINIC`  text = `Primary Care` )
      ( name = `SPECIAL`   parent = `CLINIC`  text = `Specialist Care` )
      ( name = `GP`        parent = `PRIMARY` text = `General Practice` )
      ( name = `PED`       parent = `PRIMARY` text = `Pediatrics` )
      ( name = `EMER`      parent = `PRIMARY` text = `Emergency Medicine` )
      ( name = `CARD`      parent = `SPECIAL` text = `Cardiology` )
      ( name = `PULM`      parent = `SPECIAL` text = `Pulmonology` )
      ( name = `ORTH`      parent = `SPECIAL` text = `Orthopedics` )
      ( name = `DERM`      parent = `SPECIAL` text = `Dermatology` ) ) ).
    result = VALUE #(
      ( version = '001' datefrom = '10000101' dateto = '20241231' text = `Clinic Organization` nodes = slice_2024 )
      ( version = '001' datefrom = '20250101' dateto = '99991231' text = `Clinic Organization` nodes = actual_2025 )
      ( version = '002' datefrom = '10000101' dateto = '20241231' text = `Clinic Organization (Plan)`
        nodes = slice_2024 )
      ( version = '002' datefrom = '20250101' dateto = '99991231' text = `Clinic Organization (Plan)`
        nodes = plan_2025 ) ).
  ENDMETHOD.

  METHOD organization.
    result = text_nodes.
    LOOP AT physicians INTO DATA(physician).
      DATA(department) = VALUE string( moves[ physician = physician-id ]-department OPTIONAL ).
      IF department IS INITIAL.
        department = SWITCH #( physician-department
                               WHEN `General Practice` THEN `GP`
                               WHEN `Pediatrics`       THEN `PED`
                               WHEN `Cardiology`       THEN `CARD`
                               WHEN `Pulmonology`      THEN `PULM`
                               WHEN `Orthopedics`      THEN `ORTH`
                               WHEN `Dermatology`      THEN `DERM`
                               ELSE `EMER` ).
      ENDIF.
      APPEND VALUE #( name = |{ physician-id WIDTH = 3 ALIGN = RIGHT PAD = '0' }| parent = department ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD add_node.
    DATA previous TYPE rshienodid.
    DATA(nodeid) = CONV rshienodid( lines( htab ) + 1 ).
    APPEND VALUE #( nodeid   = nodeid
                    iobjnm   = COND #( WHEN node-text IS INITIAL THEN 'ZCLDOC' ELSE '0HIER_NODE' )
                    nodename = node-name
                    tlevel   = tlevel
                    parentid = parentid ) TO htab.
    LOOP AT nodes INTO DATA(child) WHERE parent = node-name.
      DATA(childid) = CONV rshienodid( lines( htab ) + 1 ).
      IF previous IS INITIAL.
        htab[ nodeid ]-childid = childid.
      ELSE.
        htab[ previous ]-nextid = childid.
      ENDIF.
      add_node( EXPORTING nodes    = nodes
                          node     = child
                          parentid = nodeid
                          tlevel   = tlevel + 1
                CHANGING  htab     = htab ).
      previous = childid.
    ENDLOOP.
  ENDMETHOD.

  METHOD department_weights.
    result = VALUE #(
      ( scope = `0-17`  key = `Pediatrics`         weight = 60 )
      ( scope = `0-17`  key = `General Practice`   weight = 15 )
      ( scope = `0-17`  key = `Pulmonology`        weight = 5 )
      ( scope = `0-17`  key = `Orthopedics`        weight = 8 )
      ( scope = `0-17`  key = `Dermatology`        weight = 7 )
      ( scope = `0-17`  key = `Emergency Medicine` weight = 5 )
      ( scope = `18-39` key = `General Practice`   weight = 45 )
      ( scope = `18-39` key = `Cardiology`         weight = 3 )
      ( scope = `18-39` key = `Pulmonology`        weight = 7 )
      ( scope = `18-39` key = `Orthopedics`        weight = 18 )
      ( scope = `18-39` key = `Dermatology`        weight = 15 )
      ( scope = `18-39` key = `Emergency Medicine` weight = 12 )
      ( scope = `40-64` key = `General Practice`   weight = 45 )
      ( scope = `40-64` key = `Cardiology`         weight = 15 )
      ( scope = `40-64` key = `Pulmonology`        weight = 10 )
      ( scope = `40-64` key = `Orthopedics`        weight = 15 )
      ( scope = `40-64` key = `Dermatology`        weight = 7 )
      ( scope = `40-64` key = `Emergency Medicine` weight = 8 )
      ( scope = `65+`   key = `General Practice`   weight = 40 )
      ( scope = `65+`   key = `Cardiology`         weight = 28 )
      ( scope = `65+`   key = `Pulmonology`        weight = 14 )
      ( scope = `65+`   key = `Orthopedics`        weight = 10 )
      ( scope = `65+`   key = `Dermatology`        weight = 3 )
      ( scope = `65+`   key = `Emergency Medicine` weight = 5 ) ).
  ENDMETHOD.

  METHOD diagnosis_weights.
    DATA(specs) = VALUE string_table(
      ( `General Practice:J06 10,J02 6,J01 4,J20 5,J11 3,I10 10,E11 7,E78 5,E03 3,M54 8,M25 3,A09 4,B34 4,F32 4,F41 4,` &&
        `Z00 6,Z23 4,Z09 4` )
      ( `Pediatrics:J06 15,J02 8,J20 4,J45 4,J11 3,A09 8,B34 8,B01 4,L20 5,S93 2,Z00 8,Z23 10` )
      ( `Cardiology:I10 12,I20 6,I25 8,I48 8,I50 6,E78 4,Z09 6` )
      ( `Pulmonology:J45 10,J44 10,J18 6,J20 4,J11 2,Z09 4` )
      ( `Orthopedics:M54 8,M17 8,M25 5,M75 5,S93 5,S52 4,S61 3,Z09 4` )
      ( `Dermatology:L20 8,L30 6,L70 6,L40 5,B34 2,Z09 2` )
      ( `Emergency Medicine:S93 6,S52 4,S61 5,S06 4,J18 3,I20 3,I48 2,A09 3,J45 2,F41 1` ) ).
    LOOP AT specs INTO DATA(spec).
      SPLIT spec AT `:` INTO DATA(department) DATA(list).
      SPLIT list AT `,` INTO TABLE DATA(entries).
      LOOP AT entries INTO DATA(entry).
        SPLIT entry AT ` ` INTO DATA(code) DATA(weight).
        APPEND VALUE #( scope = department key = code weight = weight ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_visits.
    " older patients and small children come more often
    DATA pool TYPE STANDARD TABLE OF i WITH EMPTY KEY.
    LOOP AT patients INTO DATA(patient).
      DO SWITCH i( patient-age_group WHEN `0-17` THEN 3 WHEN `18-39` THEN 2 WHEN `40-64` THEN 3 ELSE 5 ) TIMES.
        APPEND patient-id TO pool.
      ENDDO.
    ENDLOOP.
    DATA(departments_by_age) = department_weights( ).
    DATA(diagnoses_by_department) = diagnosis_weights( ).
    DATA(visit_types) = VALUE ty_t_weight( ( key = `Outpatient` weight = 60 ) ( key = `Follow-up` weight = 25 )
                                           ( key = `Telehealth` weight = 15 ) ).
    CLEAR visits.
    DATA(day) = c_first_day.
    WHILE day <= c_last_day.
      " 0 is Monday: 1 January 1900 was one
      DATA(weekday) = ( day - CONV d( '19000101' ) ) MOD 7.
      DATA(month) = CONV i( day+4(2) ).
      DATA(winter) = xsdbool( month = 12 OR month <= 2 ).
      DATA(base) = SWITCH i( weekday WHEN 5 THEN 16 WHEN 6 THEN 7 ELSE 52 ).
      DATA(visit_count) = base + random( base DIV 5 + 1 ) - 1.
      IF winter = abap_true.
        visit_count = visit_count + visit_count DIV 5.
      ELSEIF month = 8.
        visit_count = visit_count - visit_count DIV 4.
      ENDIF.
      IF day(4) = '2025'.
        visit_count = visit_count + visit_count DIV 20.
      ENDIF.

      DO visit_count TIMES.
        DATA(visit) = VALUE ty_visit( day = day patient = pool[ random( lines( pool ) ) ] ).
        DATA(age_group) = patients[ visit-patient ]-age_group.
        " Sundays only the emergency department, Saturdays general practice too
        DATA(department) = SWITCH string( weekday
          WHEN 6 THEN `Emergency Medicine`
          WHEN 5 THEN pick( VALUE #( ( key = `General Practice` weight = 40 ) ( key = `Emergency Medicine` weight = 60 ) ) )
          ELSE pick( VALUE #( FOR w IN departments_by_age WHERE ( scope = age_group ) ( key = w-key weight = w-weight ) ) ) ).
        DATA(staff) = VALUE ty_t_physician( FOR p IN physicians WHERE ( department = department ) ( p ) ).
        visit-physician = staff[ random( lines( staff ) ) ]-id.
        " respiratory diseases are three times as frequent in winter
        DATA(candidates) = VALUE ty_t_weight( ).
        LOOP AT diagnoses_by_department INTO DATA(weight) WHERE scope = department.
          DATA(chapter) = diagnoses[ code = weight-key ]-chapter.
          APPEND VALUE #( key = weight-key
                          weight = COND #( WHEN winter = abap_true AND chapter = `Respiratory` THEN weight-weight * 3
                                           ELSE weight-weight ) ) TO candidates.
        ENDLOOP.
        visit-diagnosis = pick( candidates ).
        chapter = diagnoses[ code = visit-diagnosis ]-chapter.
        visit-visit_type = COND #( WHEN department = `Emergency Medicine` THEN `Emergency` ELSE pick( visit_types ) ).
        IF visit-visit_type = `Telehealth` AND department = `Orthopedics`.
          visit-visit_type = `Outpatient`.
        ENDIF.

        CASE visit-visit_type.
          WHEN `Emergency`.
            visit-duration = 50 + random( 190 ).
            visit-wait = 10 + random( 170 ).
          WHEN `Follow-up`.
            visit-duration = 9 + random( 12 ).
            visit-wait = 4 + random( 21 ).
          WHEN `Telehealth`.
            visit-duration = 9 + random( 7 ).
            visit-wait = random( 11 ) - 1.
          WHEN OTHERS.
            visit-duration = 14 + random( 17 ).
            visit-wait = 4 + random( 36 ).
        ENDCASE.
        visit-labs = COND #( WHEN visit-visit_type = `Telehealth` THEN 0
                             WHEN visit-visit_type = `Emergency` THEN random( 6 )
                             WHEN chapter = `Circulatory` OR chapter = `Endocrine and metabolic` THEN 1 + random( 4 )
                             WHEN chapter = `Respiratory` THEN random( 3 ) - 1
                             ELSE random( 2 ) - 1 ).
        visit-charges = SWITCH i( visit-visit_type WHEN `Emergency` THEN 350 WHEN `Follow-up` THEN 50
                                                   WHEN `Telehealth` THEN 40 ELSE 80 )
                        + visit-labs * c_lab_price + visit-duration * c_minute_price.

        " BW's blank member: no diagnosis recorded yet, triage without physician, a patient not identified
        IF random( 100 ) = 1.
          CLEAR visit-diagnosis.
        ENDIF.
        IF department = `Emergency Medicine` AND random( 100 ) <= 3.
          CLEAR visit-physician.
        ENDIF.
        IF department = `Emergency Medicine` AND random( 100 ) <= 2.
          CLEAR visit-patient.
        ENDIF.
        IF random( 200 ) = 1.
          CLEAR visit-visit_type.
        ENDIF.
        APPEND visit TO visits.
      ENDDO.
      day = day + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD limit_visits.
    DATA(total) = CONV int8( lines( visits ) ).
    IF max_visits <= 0 OR max_visits >= total.
      RETURN.
    ENDIF.
    DATA kept TYPE ty_t_visit.
    " the n-th visit is kept when n * max_visits / total reaches the next whole number
    LOOP AT visits INTO DATA(visit).
      IF ( sy-tabix * max_visits ) DIV total > ( ( sy-tabix - 1 ) * max_visits ) DIV total.
        APPEND visit TO kept.
      ENDIF.
    ENDLOOP.
    visits = kept.
  ENDMETHOD.

  METHOD master_data.
    DATA(patient_rows) = VALUE ty_t_row( FOR p IN patients
      ( VALUE #( ( |{ p-id }| ) ( p-name ) ( p-sex ) ( |{ p-birth_year }| ) ( p-age_group ) ( p-blood ) ( p-insurance )
                 ( p-city ) ( p-region ) ) ) ).
    DATA(physician_rows) = VALUE ty_t_row( FOR d IN physicians
      ( VALUE #( ( |{ d-id }| ) ( d-name ) ( d-department ) ( |{ d-years }| ) ) ) ).
    DATA(diagnosis_rows) = VALUE ty_t_row( FOR g IN diagnoses
      ( VALUE #( ( g-code ) ( g-name ) ( g-diagnosis_group ) ( g-chapter ) ) ) ).
    DATA(type_rows) = VALUE ty_t_row( ( VALUE #( ( `Outpatient` ) ( `In person` ) ) )
                                      ( VALUE #( ( `Follow-up` ) ( `In person` ) ) )
                                      ( VALUE #( ( `Emergency` ) ( `In person` ) ) )
                                      ( VALUE #( ( `Telehealth` ) ( `Remote` ) ) ) ).
    DATA(month_names) = VALUE string_table( ( `January` ) ( `February` ) ( `March` ) ( `April` ) ( `May` ) ( `June` )
                                            ( `July` ) ( `August` ) ( `September` ) ( `October` ) ( `November` )
                                            ( `December` ) ).
    DATA(day_names) = VALUE string_table( ( `Monday` ) ( `Tuesday` ) ( `Wednesday` ) ( `Thursday` ) ( `Friday` )
                                          ( `Saturday` ) ( `Sunday` ) ).
    DATA date_rows TYPE ty_t_row.
    DATA(day) = c_first_day.
    WHILE day <= c_last_day.
      DATA(month) = CONV i( day+4(2) ).
      DATA(january) = CONV d( |{ day(4) }0101| ).
      " weeks counted from 1 January, so every week belongs to one year
      APPEND VALUE #( ( |{ day }| ) ( |{ day(4) }-{ day+4(2) }-{ day+6(2) }| )
                      ( day_names[ ( day - CONV d( '19000101' ) ) MOD 7 + 1 ] ) ( month_names[ month ] )
                      ( |{ day(4) }| ) ( |Q{ ( month - 1 ) DIV 3 + 1 }| ) ( |{ month }| )
                      ( |{ ( day - january ) DIV 7 + 1 }| ) ( |{ CONV i( day+6(2) ) }| ) ) TO date_rows.
      day = day + 1.
    ENDWHILE.
    result = VALUE #(
      ( iobjnm = 'ZCLPAT' attributes = VALUE #( ( 'ZCLPNAME' ) ( 'ZCLSEX' ) ( 'ZCLBYEAR' ) ( 'ZCLAGEGR' ) ( 'ZCLBLOOD' )
                                                ( 'ZCLINSUR' ) ( 'ZCLCITY' ) ( 'ZCLREGIO' ) )
        rows = patient_rows )
      ( iobjnm = 'ZCLDOC' attributes = VALUE #( ( 'ZCLDNAME' ) ( 'ZCLDEPT' ) ( 'ZCLEXPER' ) ) rows = physician_rows )
      ( iobjnm = 'ZCLDIAG' attributes = VALUE #( ( 'ZCLDTEXT' ) ( 'ZCLDGRP' ) ( 'ZCLDCHAP' ) ) rows = diagnosis_rows )
      ( iobjnm = 'ZCLVTYPE' attributes = VALUE #( ( 'ZCLSETNG' ) ) rows = type_rows )
      ( iobjnm = 'ZCLDATE' attributes = VALUE #( ( 'ZCLTHEDT' ) ( 'ZCLDAYNM' ) ( 'ZCLMONNM' ) ( 'ZCLYEAR' ) ( 'ZCLQTR' )
                                                 ( 'ZCLMONTH' ) ( 'ZCLWEEK' ) ( 'ZCLDAYOM' ) )
        rows = date_rows ) ).
  ENDMETHOD.

  METHOD calendar.
    DATA week TYPE scal-week.
    result-calday     = day.
    result-calyear    = day(4).
    result-calmonth   = day(6).
    result-calquarter = |{ day(4) }{ ( day+4(2) - 1 ) DIV 3 + 1 }|.
    CALL FUNCTION 'DATE_GET_WEEK'
      EXPORTING
        date         = day
      IMPORTING
        week         = week
      EXCEPTIONS
        date_invalid = 1
        OTHERS       = 2.
    IF sy-subrc = 0.
      result-calweek = week.
    ENDIF.
  ENDMETHOD.

  METHOD delete_all.
    " the providers and the views use the characteristics, so they go first
    delete_adso( ).
    delete_cube( ).
    delete_views( ).
    delete_hierarchies( ).
    delete_infoobjects( ).
  ENDMETHOD.

  METHOD delete_cube.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA subrc TYPE sysubrc.
    SELECT SINGLE infocube FROM rsdcube WHERE infocube = @c_cube INTO @DATA(found).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    CALL FUNCTION 'IWP_ICUBE_DELETE'
      EXPORTING
        i_infocube = c_cube
      IMPORTING
        e_subrc    = subrc
      TABLES
        et_return  = return.
    write( |delete InfoCube { found }: { COND string( WHEN subrc = 0 THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
    IF subrc <> 0.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD delete_adso.
    IF cl_rso_adso_api=>exist( c_adso ) <> rs_c_true.
      RETURN.
    ENDIF.
    TRY.
        cl_rso_adso_api=>delete( i_adsonm         = c_adso
                                 i_with_cto       = rs_c_false
                                 i_force_deletion = rs_c_true ).
        COMMIT WORK AND WAIT.
        write( |delete aDSO { c_adso }: done| ).
      CATCH cx_rs_all_msg INTO DATA(error).
        ROLLBACK WORK.
        write( |delete aDSO { c_adso }: FAILED| ).
        write_exception( error ).
    ENDTRY.
  ENDMETHOD.

  METHOD delete_views.
    " only the views of our characteristics: the time characteristics' views are shared with other providers
    DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).
    LOOP AT dimension_characteristics( ) INTO DATA(iobjnm).
      TRY.
          IF generator->delete( iobjnm ) = abap_true.
            write( |delete view of { iobjnm }: done| ).
          ENDIF.
        CATCH cx_dd_ddl_exception INTO DATA(error).
          write( |delete view of { iobjnm }: FAILED, { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD delete_hierarchies.
    DATA messages TYPE ty_t_ndi_message.
    DATA subrc TYPE sy-subrc.
    LOOP AT characteristics( ) INTO DATA(cha) WHERE hierarchies = abap_true.
      SELECT DISTINCT hieid FROM rshiedir WHERE iobjnm = @cha-name INTO TABLE @DATA(hieids).
      LOOP AT hieids INTO DATA(hieid).
        CLEAR messages.
        CALL FUNCTION 'RSNDI_SHIE_DELETE'
          EXPORTING
            i_s_hiekey   = VALUE rssh_s_hiekey( hieid = hieid-hieid )
          IMPORTING
            e_subrc      = subrc
          TABLES
            e_t_messages = messages.
        IF subrc = 0.
          COMMIT WORK AND WAIT.
        ELSE.
          ROLLBACK WORK.
          write( |delete hierarchy { hieid-hieid } of { cha-name }: FAILED, subrc { subrc }| ).
          write_ndi_messages( messages ).
        ENDIF.
      ENDLOOP.
      IF hieids IS NOT INITIAL.
        write( |delete hierarchies of { cha-name }: { lines( hieids ) } requested| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD delete_infoobjects.
    DATA iobjnms TYPE rsd_t_c30.
    DATA messages TYPE rs_t_msg.
    DATA subrc TYPE sy-subrc.
    LOOP AT all_iobjnm( ) INTO DATA(iobjnm).
      SELECT SINGLE iobjnm FROM rsdiobj WHERE iobjnm = @iobjnm INTO @DATA(found) ##NEEDED.
      IF sy-subrc = 0.
        APPEND iobjnm TO iobjnms.
      ENDIF.
    ENDLOOP.
    IF iobjnms IS INITIAL.
      RETURN.
    ENDIF.
    CALL FUNCTION 'RSDG_IOBJ_MULTI_DELETE'
      EXPORTING
        i_t_iobjnm        = iobjnms
        i_check_dependent = rs_c_false
        i_manual          = rs_c_false
      IMPORTING
        e_t_msg           = messages
        e_subrc           = subrc.
    write( |delete InfoObjects: { lines( iobjnms ) } requested, subrc { subrc }| ).
    IF subrc <> 0.
      write_messages( messages ).
    ENDIF.
  ENDMETHOD.

  METHOD ensure_infoarea.
    SELECT SINGLE infoarea FROM rsdarea WHERE infoarea = @c_infoarea AND objvers = 'A' INTO @DATA(found) ##NEEDED.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    NEW cl_new_awb_area( )->if_rsawbn_folder_tree~create_node(
      EXPORTING  i_parentname      = ''
                 i_nodename        = CONV #( c_infoarea )
                 i_txtsh           = 'Clinic'
                 i_txtlg           = 'Clinic demo data'
                 i_insertbehaviour = '0'
      EXCEPTIONS cancelled         = 1
                 OTHERS            = 2 ).
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      write( |InfoArea { c_infoarea } created| ).
    ELSE.
      write( |InfoArea { c_infoarea } FAILED, subrc { sy-subrc }, { sy-msgid } { sy-msgno } { sy-msgv1 }| ).
    ENDIF.
  ENDMETHOD.

  METHOD create_characteristic.
    DATA return TYPE bapiret2_t.
    DATA return_line TYPE bapiret2.
    DATA iobj TYPE bapi6108-infoobject.
    DATA attributes TYPE STANDARD TABLE OF bapi6108at WITH DEFAULT KEY.
    DATA(datatp) = COND datatype_d( WHEN cha-datatp IS INITIAL THEN 'CHAR' ELSE cha-datatp ).
    DATA(details) = VALUE bapi6108(
      infoobject = cha-name
      version    = rs_c_objvers-modified
      type       = rsd_c_objtp-charact
      textshort  = cha-text
      textlong   = cha-text
      infoarea   = c_infoarea
      chabasnm   = cha-name
      datatp     = datatp
      intlen     = cha-leng
      leng       = cha-leng
      outputlen  = cha-leng
      lowercase  = COND #( WHEN datatp = 'CHAR' THEN rs_c_true )
      attribfl   = COND #( WHEN cha-attributes IS NOT INITIAL THEN rs_c_true )
      hietabfl   = cha-hierarchies
      hieverfl   = cha-hierarchies
      hienmtfl   = cha-hierarchies
      authrelfl  = cha-auth_relevant ).
    LOOP AT cha-attributes INTO DATA(attribute).
      APPEND VALUE #( chabasnm = cha-name
                      objvers  = rs_c_objvers-modified
                      attrinm  = attribute
                      posit    = sy-tabix
                      attritp  = 'DIS'
                      f4order  = sy-tabix
                      atrtimfl = '0' ) TO attributes.
    ENDLOOP.
    CALL FUNCTION 'BAPI_IOBJ_CREATE'
      EXPORTING
        details     = details
      IMPORTING
        infoobject  = iobj
        return      = return_line
      TABLES
        attributes  = attributes
        returntable = return.
    IF iobj IS INITIAL.
      write( |create { cha-name }: FAILED| ).
      APPEND return_line TO return.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD create_key_figure.
    DATA return TYPE bapiret2_t.
    DATA return_line TYPE bapiret2.
    DATA iobj TYPE bapi6108-infoobject.
    DATA(details) = VALUE bapi6108(
      infoobject = kyf-name
      version    = rs_c_objvers-modified
      type       = rsd_c_objtp-keyfigure
      textshort  = kyf-text
      textlong   = kyf-text
      infoarea   = c_infoarea
      kyftp      = 'NUM'
      datatp     = 'DEC'
      intlen     = 17
      leng       = 17
      decimals   = 2
      aggrgen    = 'SUM'
      aggrexc    = 'SUM' ).
    CALL FUNCTION 'BAPI_IOBJ_CREATE'
      EXPORTING
        details     = details
      IMPORTING
        infoobject  = iobj
        return      = return_line
      TABLES
        returntable = return.
    IF iobj IS INITIAL.
      write( |create { kyf-name }: FAILED| ).
      APPEND return_line TO return.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD activate_infoobjects.
    DATA infoobjects TYPE STANDARD TABLE OF bapi6108io WITH DEFAULT KEY.
    DATA errors TYPE STANDARD TABLE OF bapi6108io WITH DEFAULT KEY.
    DATA return TYPE bapiret2_t.
    LOOP AT all_iobjnm( ) INTO DATA(iobjnm).
      APPEND iobjnm TO infoobjects.
    ENDLOOP.
    CALL FUNCTION 'BAPI_IOBJ_ACTIVATE_MULTIPLE'
      TABLES
        infoobjects       = infoobjects
        return            = return
        infoobjects_error = errors.
    write( |activate InfoObjects: { lines( infoobjects ) } requested, { lines( errors ) } in error| ).
    IF errors IS NOT INITIAL.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD create_cube.
    DATA dimension_table TYPE STANDARD TABLE OF bapi6112di WITH DEFAULT KEY.
    DATA infoobjects TYPE STANDARD TABLE OF bapi6112io WITH DEFAULT KEY.
    DATA dimension_infoobjects TYPE STANDARD TABLE OF bapi6112dio WITH DEFAULT KEY.
    DATA valid TYPE STANDARD TABLE OF rsdicvaliobj WITH DEFAULT KEY.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA cube TYPE bapi6112-infocube.
    DATA position TYPE rsposit.
    LOOP AT dimensions( ) INTO DATA(dime).
      DATA(dimension) = CONV rsdimension( |{ c_cube }{ dime-suffix }| ).
      APPEND VALUE #( infocube  = c_cube
                      objvers   = rs_c_objvers-modified
                      dimension = dimension
                      textlong  = dime-text
                      iobjtp    = dime-iobjtp ) TO dimension_table.
      LOOP AT dime-iobjnms INTO DATA(iobjnm).
        position = position + 1.
        APPEND VALUE #( infocube   = c_cube
                        objvers    = rs_c_objvers-modified
                        dimension  = dimension
                        posit      = sy-tabix
                        infoobject = iobjnm ) TO dimension_infoobjects.
        APPEND VALUE #( infocube   = c_cube
                        objvers    = rs_c_objvers-modified
                        posit      = position
                        infoobject = iobjnm
                        iobjtp     = dime-iobjtp ) TO infoobjects.
      ENDLOOP.
    ENDLOOP.
    LOOP AT key_figures( ) INTO DATA(kyf).
      position = position + 1.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = rs_c_objvers-modified
                      posit      = position
                      infoobject = kyf-name
                      iobjtp     = rsd_c_objtp-keyfigure ) TO infoobjects.
    ENDLOOP.
    DATA(details) = VALUE bapi6112( infocube = c_cube
                                    objvers  = rs_c_objvers-modified
                                    textlong = 'Clinic Visits'
                                    infoarea = c_infoarea
                                    cubetype = rsd_c_cubetype-basic_ic ).
    CALL FUNCTION 'BAPI_CUBE_CREATE'
      EXPORTING
        details              = details
      IMPORTING
        infocube             = cube
      TABLES
        dimensions           = dimension_table
        infoobjects          = infoobjects
        dimensioninfoobjects = dimension_infoobjects
        return               = return
        rsdicvaliobj         = valid.
    write( |create InfoCube { c_cube }: { COND string( WHEN cube IS NOT INITIAL THEN `saved` ELSE `FAILED` ) }| ).
    IF cube IS INITIAL.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD activate_cube.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA active TYPE bapi6112-activfl.
    CALL FUNCTION 'BAPI_CUBE_ACTIVATE'
      EXPORTING
        infocube              = c_cube
      IMPORTING
        activation_successful = active
      TABLES
        return                = return.
    write( |activate InfoCube { c_cube }: { COND string( WHEN active = abap_true THEN `active` ELSE `FAILED` ) }| ).
    IF active <> abap_true.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD load_master_data.
    " rows of the attribute table (P table); writing a key generates its SID. The blank key keeps BW's own record.
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DATA data TYPE REF TO data.
    DATA attributes TYPE rsd_t_iobjnm.
    DATA messages TYPE rsarr_t_idocstate.
    DATA subrc TYPE sy-subrc.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( |/BIC/P{ md-iobjnm }| ) ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    LOOP AT md-rows INTO DATA(fields).
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT |/BIC/{ md-iobjnm }| OF STRUCTURE <row> TO <value>.
      <value> = fields[ 1 ].
      ASSIGN COMPONENT 'OBJVERS' OF STRUCTURE <row> TO <value>.
      <value> = rs_c_objvers-active.
      LOOP AT md-attributes INTO DATA(attribute).
        ASSIGN COMPONENT |/BIC/{ attribute }| OF STRUCTURE <row> TO <value>.
        <value> = fields[ sy-tabix + 1 ].
      ENDLOOP.
    ENDLOOP.
    attributes = VALUE #( FOR a IN md-attributes ( iobjnm = a ) ).
    CALL FUNCTION 'RSDMD_WRITE_ATTRIBUTES_TEXTS'
      EXPORTING
        i_iobjnm               = md-iobjnm
        i_tabclass             = rsdmd_c_tabclass-md
        i_t_attr               = attributes
      IMPORTING
        e_t_idocstate          = messages
        e_subrc                = subrc
      TABLES
        i_t_table              = <table>
      EXCEPTIONS
        attribute_name_error   = 1
        iobj_not_found         = 2
        generate_program_error = 3
        OTHERS                 = 4.
    DATA(ok) = xsdbool( sy-subrc = 0 AND subrc = 0 ).
    IF ok = abap_true.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.
    write( |load { md-iobjnm }: { lines( <table> ) } records, | &&
           |{ COND string( WHEN ok = abap_true THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
  ENDMETHOD.

  METHOD load_hierarchy.
    DATA htab TYPE ty_t_htab.
    DATA texts TYPE rsndi_t_hiedirt.
    DATA node_texts TYPE rsndi_t_thiernode.
    DATA messages TYPE ty_t_ndi_message.
    DATA subrc TYPE sy-subrc.
    DATA hieid TYPE rshieid.
    add_node( EXPORTING nodes    = hierarchy-nodes
                        node     = hierarchy-nodes[ parent = `` ]
                        parentid = 0
                        tlevel   = 1
              CHANGING  htab     = htab ).
    texts = VALUE #( ( langu = 'E' txtsh = hierarchy-text txtmd = hierarchy-text txtlg = hierarchy-text ) ).
    node_texts = VALUE #( FOR n IN hierarchy-nodes WHERE ( text IS NOT INITIAL )
                          ( langu = 'E' nodename = n-name txtsh = n-text txtmd = n-text txtlg = n-text ) ).
    DATA(header) = VALUE rsndi_s_hierupdate( hienm    = c_hierarchy
                                             version  = hierarchy-version
                                             iobjnm   = 'ZCLDOC'
                                             datefrom = hierarchy-datefrom
                                             dateto   = hierarchy-dateto ).
    CALL FUNCTION 'RSNDI_SHIE_STRUCTURE_UPDATE4'
      EXPORTING
        i_s_hiehead   = header
        i_t_hiedirt   = texts
        i_t_hierstruc = htab
        i_t_thiernode = node_texts
        i_t_nodenames = VALUE rsndi_t_nodenmstr( )
        i_t_hierintvl = VALUE rsndi_t_jtabstr( )
        i_t_nodeattr  = VALUE rssh_t_nodeattr( )
        i_t_level     = VALUE rsndi_t_hielvt( )
      IMPORTING
        e_subrc       = subrc
        e_hieid       = hieid
        e_t_messages  = messages.
    IF subrc = 0.
      COMMIT WORK AND WAIT.
      CALL FUNCTION 'RSNDI_SHIE_ACTIVATE'
        EXPORTING
          i_hieid      = hieid
        IMPORTING
          e_subrc      = subrc
        TABLES
          e_t_messages = messages.
    ENDIF.
    IF subrc = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.
    write( |hierarchy { c_hierarchy } version { hierarchy-version }, { hierarchy-datefrom DATE = ISO } to | &&
           |{ hierarchy-dateto DATE = ISO }: { lines( htab ) } nodes, | &&
           |{ COND string( WHEN subrc = 0 THEN `active` ELSE |FAILED, subrc { subrc }| ) }| ).
    IF subrc <> 0.
      write_ndi_messages( messages ).
    ENDIF.
  ENDMETHOD.

  METHOD load_cube.
    " RSDRI_CUBE_WRITE_PACKAGE takes rows of the cube's T-view (/BIC/V<cube>2): InfoObject names without /BIC/
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DATA data TYPE REF TO data.
    DATA request TYPE rsrequnr.
    DATA records TYPE i.
    DATA messages TYPE rsdri_ts_msg.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( |/BIC/V{ c_cube }2| ) ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    LOOP AT visits INTO DATA(visit).
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT 'ZCLPAT' OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-patient <> 0 THEN |{ visit-patient }| ).
      ASSIGN COMPONENT 'ZCLDOC' OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-physician <> 0 THEN |{ visit-physician }| ).
      ASSIGN COMPONENT 'ZCLDIAG' OF STRUCTURE <row> TO <value>.
      <value> = visit-diagnosis.
      ASSIGN COMPONENT 'ZCLVTYPE' OF STRUCTURE <row> TO <value>.
      <value> = visit-visit_type.
      ASSIGN COMPONENT 'ZCLDATE' OF STRUCTURE <row> TO <value>.
      <value> = visit-day.
      ASSIGN COMPONENT 'ZCLVISNO' OF STRUCTURE <row> TO <value>.
      <value> = 1.
      ASSIGN COMPONENT 'ZCLDUR' OF STRUCTURE <row> TO <value>.
      <value> = visit-duration.
      ASSIGN COMPONENT 'ZCLWAIT' OF STRUCTURE <row> TO <value>.
      <value> = visit-wait.
      ASSIGN COMPONENT 'ZCLLABS' OF STRUCTURE <row> TO <value>.
      <value> = visit-labs.
      ASSIGN COMPONENT 'ZCLCHRG' OF STRUCTURE <row> TO <value>.
      <value> = visit-charges.
    ENDLOOP.
    CALL FUNCTION 'RSDRI_CUBE_WRITE_PACKAGE'
      EXPORTING
        i_infocube         = c_cube
        i_curr_conversion  = rs_c_false
      IMPORTING
        e_requid           = request
        e_records          = records
        e_ts_msg           = messages
      CHANGING
        c_t_data           = <table>
      EXCEPTIONS
        infocube_not_found = 1
        illegal_input      = 2
        rollback_error     = 3
        duplicate_records  = 4
        request_locked     = 5
        not_transactional  = 6
        inherited_error    = 7
        OTHERS             = 8.
    DATA(subrc) = sy-subrc.
    IF subrc = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.
    write( |load { c_cube }: { lines( <table> ) } records sent, { records } written, | &&
           |{ COND string( WHEN subrc = 0 THEN |request { request }| ELSE |FAILED, subrc { subrc }| ) }| ).
  ENDMETHOD.

  METHOD verify.
    DATA rows TYPE i.
    DATA total TYPE p LENGTH 16 DECIMALS 2.
    IF source IS INITIAL.
      RETURN.
    ENDIF.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( source ) ).
    DATA(list) = |COUNT(*), SUM( { iobj_field( struct = line iobjnm = 'ZCLDUR' ) } )|.
    SELECT SINGLE (list) FROM (source) INTO (@rows, @total).
    write( |{ source }: { rows } rows, duration { total } (generated: { lines( visits ) } visits, duration | &&
           |{ REDUCE i( INIT s = 0 FOR v IN visits NEXT s = s + v-duration ) })| ).
  ENDMETHOD.

  METHOD generate_views.
    DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).
    TRY.
        result = generator->generate_cube( c_cube ).
        LOOP AT VALUE ty_t_iobjnm( ( '0CALWEEK' ) ( '0CALMONTH' ) ( '0CALQUARTER' ) ( '0CALYEAR' ) ) INTO DATA(iobjnm).
          APPEND generator->generate( iobjnm ) TO result.
        ENDLOOP.
      CATCH cx_dd_ddl_exception INTO DATA(error).
        write( |views: FAILED, { error->get_text( ) }| ).
    ENDTRY.
    LOOP AT result INTO DATA(view).
      write( |view of { view-characteristic }: { view-view_name }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD create_adso.
    DATA objects TYPE cl_rso_adso_api=>tn_t_object.
    DATA messages TYPE rs_t_msg.
    DATA error TYPE REF TO cx_root.
    " the characteristics of the cube with BW's calendar in place of the date; 0CALDAY has no SID table, so no view
    objects = VALUE #( FOR c IN VALUE ty_t_iobjnm( ( 'ZCLPAT' ) ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ( 'ZCLVTYPE' ) ( '0CALDAY' )
                                                   ( '0CALWEEK' ) ( '0CALMONTH' ) ( '0CALQUARTER' ) ( '0CALYEAR' ) )
                       ( iobjnm = c sid_determination_mode = 'S' ) ).
    LOOP AT key_figures( ) INTO DATA(kyf).
      APPEND VALUE #( iobjnm = kyf-name aggregation = 'SUM' ) TO objects.
    ENDLOOP.
    TRY.
        DATA(flags) = cl_rso_adso_api=>get_adso_flags_from_model_tmpl( cl_rso_adso_api=>tn_c_model_tmpl-cube_like ).
        cl_rso_adso_api=>create( EXPORTING i_adsonm      = c_adso
                                           i_text        = 'Clinic Visits (aDSO)'
                                           i_infoarea    = c_infoarea
                                           i_s_adsoflags = flags
                                           i_t_object    = objects
                                           i_t_dimension = VALUE #( )
                                           i_with_cto    = rs_c_false
                                 IMPORTING e_t_msg       = messages ).
        COMMIT WORK AND WAIT.
        write( |create aDSO { c_adso }: active| ).
      CATCH cx_rs_all_msg cx_rs_failed INTO error.
        ROLLBACK WORK.
        write( |create aDSO { c_adso }: FAILED| ).
        write_exception( error ).
        RETURN.
    ENDTRY.
    write_messages( VALUE #( FOR m IN messages WHERE ( msgty = 'E' OR msgty = 'A' ) ( m ) ) ).
  ENDMETHOD.

  METHOD adso_table.
    TRY.
        DATA(tables) = cl_rso_adso=>get_tablnm( c_adso ).
        result = VALUE #( tables[ dsotabtype = type ]-name OPTIONAL ).
      CATCH cx_rs_not_found.
        CLEAR result.
    ENDTRY.
    IF result IS INITIAL.
      write( |aDSO { c_adso }: no { type } table| ).
    ENDIF.
  ENDMETHOD.

  METHOD load_adso.
    " the aDSO holds characteristic values, not SIDs; the write API runs no transformation, so the calendar is set here
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DATA data TYPE REF TO data.
    DATA inserted TYPE int4.
    DATA messages TYPE rs_t_msg.
    DATA activation_requests TYPE rsdso_t_tsn.
    DATA request TYPE rspm_request_tsn.
    DATA(inbound) = adso_table( cl_rsdso_dsotable=>c_tabtype_aq ).
    IF inbound IS INITIAL.
      RETURN.
    ENDIF.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( inbound ) ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    DATA(patient) = iobj_field( struct = line iobjnm = 'ZCLPAT' ).
    DATA(physician) = iobj_field( struct = line iobjnm = 'ZCLDOC' ).
    DATA(diagnosis) = iobj_field( struct = line iobjnm = 'ZCLDIAG' ).
    DATA(visit_type) = iobj_field( struct = line iobjnm = 'ZCLVTYPE' ).
    DATA(visit_number) = iobj_field( struct = line iobjnm = 'ZCLVISNO' ).
    DATA(duration) = iobj_field( struct = line iobjnm = 'ZCLDUR' ).
    DATA(wait) = iobj_field( struct = line iobjnm = 'ZCLWAIT' ).
    DATA(labs) = iobj_field( struct = line iobjnm = 'ZCLLABS' ).
    DATA(charges) = iobj_field( struct = line iobjnm = 'ZCLCHRG' ).
    DATA(calday) = iobj_field( struct = line iobjnm = '0CALDAY' ).
    DATA(calweek) = iobj_field( struct = line iobjnm = '0CALWEEK' ).
    DATA(calmonth) = iobj_field( struct = line iobjnm = '0CALMONTH' ).
    DATA(calquarter) = iobj_field( struct = line iobjnm = '0CALQUARTER' ).
    DATA(calyear) = iobj_field( struct = line iobjnm = '0CALYEAR' ).
    LOOP AT visits INTO DATA(visit).
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT patient OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-patient <> 0 THEN |{ visit-patient }| ).
      ASSIGN COMPONENT physician OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-physician <> 0 THEN |{ visit-physician }| ).
      ASSIGN COMPONENT diagnosis OF STRUCTURE <row> TO <value>.
      <value> = visit-diagnosis.
      ASSIGN COMPONENT visit_type OF STRUCTURE <row> TO <value>.
      <value> = visit-visit_type.
      ASSIGN COMPONENT visit_number OF STRUCTURE <row> TO <value>.
      <value> = 1.
      ASSIGN COMPONENT duration OF STRUCTURE <row> TO <value>.
      <value> = visit-duration.
      ASSIGN COMPONENT wait OF STRUCTURE <row> TO <value>.
      <value> = visit-wait.
      ASSIGN COMPONENT labs OF STRUCTURE <row> TO <value>.
      <value> = visit-labs.
      ASSIGN COMPONENT charges OF STRUCTURE <row> TO <value>.
      <value> = visit-charges.
      DATA(calendar) = calendar( visit-day ).
      ASSIGN COMPONENT calday OF STRUCTURE <row> TO <value>.
      <value> = calendar-calday.
      ASSIGN COMPONENT calweek OF STRUCTURE <row> TO <value>.
      <value> = calendar-calweek.
      ASSIGN COMPONENT calmonth OF STRUCTURE <row> TO <value>.
      <value> = calendar-calmonth.
      ASSIGN COMPONENT calquarter OF STRUCTURE <row> TO <value>.
      <value> = calendar-calquarter.
      ASSIGN COMPONENT calyear OF STRUCTURE <row> TO <value>.
      <value> = calendar-calyear.
    ENDLOOP.
    CALL FUNCTION 'RSDSO_WRITE_API'
      EXPORTING
        i_adsonm            = c_adso
        i_activate_data     = rs_c_true
        it_data             = <table>
      IMPORTING
        e_lines_inserted    = inserted
        et_msg              = messages
        e_upd_req_tsn       = request
        et_act_req_tsn      = activation_requests
      EXCEPTIONS
        write_failed        = 1
        activation_failed   = 2
        datastore_not_found = 3
        OTHERS              = 4.
    DATA(subrc) = sy-subrc.
    IF subrc = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
    ENDIF.
    write( |load aDSO { c_adso }: { lines( <table> ) } records sent, { inserted } written, | &&
           |{ lines( activation_requests ) } activated, | &&
           |{ COND string( WHEN subrc = 0 THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
    IF subrc <> 0.
      write_messages( messages ).
    ENDIF.
  ENDMETHOD.

  METHOD key_columns.
    result = COND #(
      WHEN adso = abap_true THEN |<KeyColumn dataType="{ data_type }" columnName="{ column }"/>|
      ELSE |<KeyColumn dataType="Integer" columnName="SID"/><NameColumn dataType="{ data_type }" columnName="{ column }"/>| ).
  ENDMETHOD.

  METHOD attribute_xml.
    result = |    <DimensionAttribute name="{ name }"| &&
             COND string( WHEN level_type IS NOT INITIAL THEN | levelType="{ level_type }"| ) &&
             |><KeyColumn dataType="{ data_type }" columnName="{ column }"/></DimensionAttribute>\n|.
  ENDMETHOD.

  METHOD view_of.
    result = VALUE #( views[ characteristic = iobjnm ]-view_name OPTIONAL ).
    IF result IS INITIAL.
      write( |schema: no view of { iobjnm }| ).
    ENDIF.
  ENDMETHOD.

  METHOD schema_xml.
    DATA(name) = COND string( WHEN adso = abap_true THEN c_adso ELSE c_cube ).
    DATA(fact_table) = COND string( WHEN adso = abap_true THEN adso_table( cl_rsdso_constants=>n_c_viewtype_reporting )
                                    ELSE |/BIC/F{ c_cube }| ).
    IF fact_table IS INITIAL.
      RETURN.
    ENDIF.
    DATA(fact) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( fact_table ) ).

    result =
      |<?xml version="1.0"?>\n| &&
      |<!-- The clinic demo, generated by ZZXXMLA1_CL_BW_CLINIC_GEN (docs/clinic-demo.md). -->\n| &&
      |<Schema name="{ name }">\n| &&
      |  <Dimension name="Patient" table="{ view_of( views = views iobjnm = 'ZCLPAT' ) }">\n| &&
      |    <DimensionAttribute name="Patient Id" usage="Key">| &&
      key_columns( adso = adso column = `ZCLPAT` data_type = `Integer` ) && |</DimensionAttribute>\n| &&
      attribute_xml( name = `Patient Name` column = `ZCLPNAME` ) &&
      attribute_xml( name = `Sex` column = `ZCLSEX` ) &&
      attribute_xml( name = `Birth Year` column = `ZCLBYEAR` data_type = `Integer` ) &&
      attribute_xml( name = `Age Group` column = `ZCLAGEGR` ) &&
      attribute_xml( name = `Blood Group` column = `ZCLBLOOD` ) &&
      attribute_xml( name = `Insurance` column = `ZCLINSUR` ) &&
      attribute_xml( name = `City` column = `ZCLCITY` ) &&
      attribute_xml( name = `Region` column = `ZCLREGIO` ) &&
      |    <Hierarchy hasAll="true" allMemberName="All Patients">\n| &&
      |      <Level name="Region" uniqueMembers="true" sourceAttribute="Region"/>\n| &&
      |      <Level name="City" uniqueMembers="false" sourceAttribute="City"/>\n| &&
      |      <Level name="Patient" uniqueMembers="true" nameColumn="ZCLPNAME" sourceAttribute="Patient Id">\n| &&
      |        <Property name="Sex" sourceAttribute="Sex"/>\n| &&
      |        <Property name="Birth Year" sourceAttribute="Birth Year"/>\n| &&
      |        <Property name="Blood Group" sourceAttribute="Blood Group"/>\n| &&
      |        <Property name="Insurance" sourceAttribute="Insurance"/>\n| &&
      |      </Level>\n| &&
      |    </Hierarchy>\n| &&
      |    <Hierarchy name="Demographics" hasAll="true" allMemberName="All Patients">\n| &&
      |      <Level name="Age Group" uniqueMembers="true" sourceAttribute="Age Group"/>\n| &&
      |      <Level name="Sex" uniqueMembers="false" sourceAttribute="Sex"/>\n| &&
      |    </Hierarchy>\n| &&
      |  </Dimension>\n| &&
      |  <Dimension name="Physician" table="{ view_of( views = views iobjnm = 'ZCLDOC' ) }">\n| &&
      |    <DimensionAttribute name="Physician Id" usage="Key">| &&
      key_columns( adso = adso column = `ZCLDOC` data_type = `Integer` ) && |</DimensionAttribute>\n| &&
      attribute_xml( name = `Physician Name` column = `ZCLDNAME` ) &&
      attribute_xml( name = `Department` column = `ZCLDEPT` ) &&
      attribute_xml( name = `Years in Practice` column = `ZCLEXPER` data_type = `Integer` ) &&
      |    <Hierarchy hasAll="true" allMemberName="All Physicians">\n| &&
      |      <Level name="Department" uniqueMembers="true" sourceAttribute="Department"/>\n| &&
      |      <Level name="Physician" uniqueMembers="true" nameColumn="ZCLDNAME" sourceAttribute="Physician Id">\n| &&
      |        <Property name="Years in Practice" sourceAttribute="Years in Practice"/>\n| &&
      |      </Level>\n| &&
      |    </Hierarchy>\n| &&
      |  </Dimension>\n| &&
      |  <Dimension name="Diagnosis" table="{ view_of( views = views iobjnm = 'ZCLDIAG' ) }">\n| &&
      |    <DimensionAttribute name="Diagnosis Code" usage="Key">| &&
      key_columns( adso = adso column = `ZCLDIAG` data_type = `String` ) && |</DimensionAttribute>\n| &&
      attribute_xml( name = `Diagnosis Name` column = `ZCLDTEXT` ) &&
      attribute_xml( name = `Diagnosis Group` column = `ZCLDGRP` ) &&
      attribute_xml( name = `Chapter` column = `ZCLDCHAP` ) &&
      |    <Hierarchy hasAll="true" allMemberName="All Diagnoses">\n| &&
      |      <Level name="Chapter" uniqueMembers="true" sourceAttribute="Chapter"/>\n| &&
      |      <Level name="Group" uniqueMembers="true" sourceAttribute="Diagnosis Group"/>\n| &&
      |      <Level name="Diagnosis" uniqueMembers="true" nameColumn="ZCLDTEXT" sourceAttribute="Diagnosis Code"/>\n| &&
      |    </Hierarchy>\n| &&
      |  </Dimension>\n| &&
      |  <Dimension name="Visit Type" table="{ view_of( views = views iobjnm = 'ZCLVTYPE' ) }">\n| &&
      |    <DimensionAttribute name="Type" usage="Key">| &&
      key_columns( adso = adso column = `ZCLVTYPE` data_type = `String` ) && |</DimensionAttribute>\n| &&
      attribute_xml( name = `Care Setting` column = `ZCLSETNG` ) &&
      |    <Hierarchy hasAll="true" allMemberName="All Visit Types">\n| &&
      |      <Level name="Care Setting" uniqueMembers="true" sourceAttribute="Care Setting"/>\n| &&
      |      <Level name="Visit Type" uniqueMembers="true" sourceAttribute="Type"/>\n| &&
      |    </Hierarchy>\n| &&
      |  </Dimension>\n|.

    DATA(usages) = VALUE string_table( ).
    IF adso = abap_false.
      " the date with its attributes: a time dimension; BW's blank member (year 0) would come first, so the default
      " member is the last year
      result = result &&
        |  <Dimension name="Time" type="TimeDimension" table="{ view_of( views = views iobjnm = 'ZCLDATE' ) }">\n| &&
        |    <DimensionAttribute name="Date Id" usage="Key" levelType="TimeDays">| &&
        key_columns( adso = adso column = `ZCLDATE` data_type = `Integer` ) && |</DimensionAttribute>\n| &&
        attribute_xml( name = `The Date` column = `ZCLTHEDT` level_type = `TimeDays` ) &&
        attribute_xml( name = `Day Name` column = `ZCLDAYNM` level_type = `TimeUndefined` ) &&
        attribute_xml( name = `Month Name` column = `ZCLMONNM` level_type = `TimeMonths` ) &&
        attribute_xml( name = `Year` column = `ZCLYEAR` data_type = `Integer` level_type = `TimeYears` ) &&
        attribute_xml( name = `Quarter` column = `ZCLQTR` level_type = `TimeQuarters` ) &&
        attribute_xml( name = `Month of Year` column = `ZCLMONTH` data_type = `Integer` level_type = `TimeMonths` ) &&
        attribute_xml( name = `Week of Year` column = `ZCLWEEK` data_type = `Integer` level_type = `TimeWeeks` ) &&
        attribute_xml( name = `Day of Month` column = `ZCLDAYOM` data_type = `Integer` level_type = `TimeDays` ) &&
        |    <Hierarchy hasAll="false" defaultMember="[Time].[2025]">\n| &&
        |      <Level name="Year" uniqueMembers="true" sourceAttribute="Year" levelType="TimeYears"/>\n| &&
        |      <Level name="Quarter" uniqueMembers="false" sourceAttribute="Quarter" levelType="TimeQuarters"/>\n| &&
        |      <Level name="Month" uniqueMembers="false" sourceAttribute="Month of Year" nameColumn="ZCLMONNM" | &&
        |levelType="TimeMonths"/>\n| &&
        |      <Level name="Day" uniqueMembers="true" sourceAttribute="The Date" levelType="TimeDays"/>\n| &&
        |    </Hierarchy>\n| &&
        |    <Hierarchy name="Weekly" hasAll="true">\n| &&
        |      <Level name="Year" uniqueMembers="true" sourceAttribute="Year" levelType="TimeYears"/>\n| &&
        |      <Level name="Week" uniqueMembers="false" sourceAttribute="Week of Year" levelType="TimeWeeks"/>\n| &&
        |      <Level name="Day" uniqueMembers="true" sourceAttribute="The Date" levelType="TimeDays"/>\n| &&
        |    </Hierarchy>\n| &&
        |  </Dimension>\n|.
      usages = VALUE #( ( |Patient:SID_ZCLPAT| ) ( |Physician:SID_ZCLDOC| ) ( |Diagnosis:SID_ZCLDIAG| )
                        ( |Visit Type:SID_ZCLVTYPE| ) ( |Time:SID_ZCLDATE| ) ).
    ELSE.
      " BW's time characteristics have no attributes: one dimension each, keyed by the value as the fact column
      DATA(calendar) = VALUE ty_t_group_weight( ( scope = `Year` key = `0CALYEAR` )
                                                ( scope = `Quarter` key = `0CALQUARTER` )
                                                ( scope = `Month` key = `0CALMONTH` )
                                                ( scope = `Week` key = `0CALWEEK` ) ).
      LOOP AT calendar INTO DATA(period).
        DATA(column) = zzxxmla1_cl_bw_view_gen=>view_column( iobj_field( struct = fact iobjnm = CONV #( period-key ) ) ).
        result = result &&
          |  <Dimension name="{ period-scope }" table="{ view_of( views = views iobjnm = CONV #( period-key ) ) }">\n| &&
          |    <DimensionAttribute name="{ period-scope }" usage="Key">| &&
          key_columns( adso = adso column = column data_type = `Integer` ) && |</DimensionAttribute>\n| &&
          |  </Dimension>\n|.
      ENDLOOP.
      LOOP AT VALUE ty_t_group_weight( ( scope = `Patient` key = `ZCLPAT` ) ( scope = `Physician` key = `ZCLDOC` )
                                       ( scope = `Diagnosis` key = `ZCLDIAG` ) ( scope = `Visit Type` key = `ZCLVTYPE` )
                                       ( LINES OF calendar ) ) INTO period.
        APPEND |{ period-scope }:{ iobj_field( struct = fact iobjnm = CONV #( period-key ) ) }| TO usages.
      ENDLOOP.
    ENDIF.

    result = result &&
      |  <Cube name="{ name }" caption="Clinic Visits{ COND string( WHEN adso = abap_true THEN ` (aDSO)` ) }" | &&
      |defaultMeasure="Visits">\n| &&
      |    <Table name="{ fact_table }"/>\n|.
    LOOP AT usages INTO DATA(usage).
      SPLIT usage AT `:` INTO DATA(dimension) DATA(foreign_key).
      result = result && |    <DimensionUsage name="{ dimension }" source="{ dimension }" foreignKey="{ foreign_key }"/>\n|.
    ENDLOOP.
    DATA(duration) = iobj_field( struct = fact iobjnm = 'ZCLDUR' ).
    result = result &&
      |    <Measure name="Visits" column="{ iobj_field( struct = fact iobjnm = 'ZCLVISNO' ) }" aggregator="sum" | &&
      |formatString="#,##0"/>\n| &&
      |    <Measure name="Duration Min" column="{ duration }" aggregator="sum" formatString="#,##0"/>\n| &&
      |    <Measure name="Waiting Min" column="{ iobj_field( struct = fact iobjnm = 'ZCLWAIT' ) }" aggregator="sum" | &&
      |formatString="#,##0"/>\n| &&
      |    <Measure name="Lab Tests" column="{ iobj_field( struct = fact iobjnm = 'ZCLLABS' ) }" aggregator="sum" | &&
      |formatString="#,##0"/>\n| &&
      |    <Measure name="Charges" column="{ iobj_field( struct = fact iobjnm = 'ZCLCHRG' ) }" aggregator="sum" | &&
      |formatString="#,##0.00"/>\n| &&
      |  </Cube>\n| &&
      |</Schema>\n|.
  ENDMETHOD.

  METHOD write_catalog.
    IF xml IS INITIAL.
      write( |catalog { catalog }: FAILED, no schema| ).
      RETURN.
    ENDIF.
    DATA(path) = |/WEB-INF/schema/{ catalog }.xml|.
    zzxxmla1_cl_files=>write( path = path content = xml ).
    DATA(datasources) = zzxxmla1_cl_files=>read( zzxxmla1_cl_files=>c_datasources )-content.
    IF datasources IS INITIAL.
      datasources = zzxxmla1_cl_files=>default_datasources( ).
    ENDIF.
    IF datasources NS |<Catalog name="{ catalog }">|.
      " into the first data source's Catalogs
      FIND FIRST OCCURRENCE OF `</Catalogs>` IN datasources MATCH OFFSET DATA(offset).
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        write( |catalog { catalog }: FAILED, { zzxxmla1_cl_files=>c_datasources } has no Catalogs| ).
        RETURN.
      ENDIF.
      datasources = substring( val = datasources len = offset ) &&
                    |  <Catalog name="{ catalog }">\n| &&
                    |        <Definition>{ path }</Definition>\n| &&
                    |      </Catalog>\n    | &&
                    substring( val = datasources off = offset ).
    ENDIF.
    zzxxmla1_cl_files=>write( path = zzxxmla1_cl_files=>c_datasources content = datasources ).
    COMMIT WORK.
    write( |catalog { catalog }: { path }| ).
  ENDMETHOD.

  METHOD iobj_field.
    DATA field TYPE rsd_fieldnm.
    CALL FUNCTION 'RSD_FIELDNM_GET_FROM_IOBJNM'
      EXPORTING
        i_name     = iobjnm
      IMPORTING
        e_ddname   = field
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    DATA(subrc) = sy-subrc.
    result = field.
    DATA(components) = struct->get_components( ).
    IF subrc <> 0 OR NOT line_exists( components[ name = result ] ).
      write( |{ iobjnm }: no field { result } in { struct->get_relative_name( ) }| ).
    ENDIF.
  ENDMETHOD.

  METHOD write_exception.
    DATA(current) = error.
    WHILE current IS BOUND.
      write( |  { current->get_text( ) }| ).
      IF current IS INSTANCE OF cx_rs_all_msg.
        DATA(with_messages) = CAST cx_rs_all_msg( current ).
        write_messages( with_messages->t_msg ).
        IF with_messages->r_log IS BOUND.
          write_messages( with_messages->r_log->get_messages( ) ).
        ENDIF.
      ENDIF.
      current = current->previous.
    ENDWHILE.
  ENDMETHOD.

  METHOD write_return.
    LOOP AT return INTO DATA(line) WHERE message IS NOT INITIAL.
      write( |  [{ line-type }] { line-message }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD write_messages.
    LOOP AT messages INTO DATA(message).
      MESSAGE ID message-msgid TYPE 'S' NUMBER message-msgno
        WITH message-msgv1 message-msgv2 message-msgv3 message-msgv4 INTO DATA(text).
      write( |  [{ message-msgty }] { text }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD write_ndi_messages.
    LOOP AT messages INTO DATA(message).
      MESSAGE ID message-msgid TYPE 'S' NUMBER message-msgno
        WITH message-msgv1 message-msgv2 message-msgv3 message-msgv4 INTO DATA(text).
      write( |  [{ message-msgty }] { text }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
