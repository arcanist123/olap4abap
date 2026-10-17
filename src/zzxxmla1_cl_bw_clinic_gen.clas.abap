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
"! - on the physician ZCLDOC, which is authorization relevant, two hierarchies: ZCLDOC_ORG (clinic > division >
"!   department > physician) and ZCLDOC_SITE (all sites > area > site > physician); version dependent, the entire
"!   hierarchy time dependent, each with two versions of two time slices,
"! - on the diagnosis ZCLDIAG, also authorization relevant, the plain hierarchy ZCLDIAG_ICD (all diagnoses > chapter >
"!   group > diagnosis), for authorizations that combine both characteristics; every value is in it (the initial one
"!   under Not recorded > No diagnosis) and the not-assigned node is suppressed,
"! - on the patient ZCLPAT the plain hierarchy ZCLPAT_PRG (care programs > program > patient) with link nodes: a
"!   patient in two programs is a leaf in both (a duplicate node, or a link node), the heart program is under chronic
"!   care and under senior care, and senior care with it under prevention (link nodes), and parents with their
"!   children below them in family care (postable nodes),
"! - the service ZCLSERV (52 services by a four-digit code, a dimension of both providers), with the plain hierarchy
"!   ZCLSERV_CAT (all services > category > ranges of codes) of intervals: overlapping ones, a linked text node with its
"!   range and a linked range, and the plain hierarchy ZCLSERV_LOC (all locations > site > room > service) whose sites
"!   and rooms are nodes of the external characteristics ZCLSITE and ZCLROOM (compounded with the site), the site
"!   NORTH next to a text node NORTH (a partner laboratory),
"! - the room ZCLROOM, compounded with the site ZCLSITE: the same rooms R01 to R04 at both sites, so a room is a member
"!   only with its site (docs/bw-schema-design-guide.md, section 3.7),
"! - the fiscal time, a dimension of its own: the fiscal year variant ZCLFISCVR (K1, K2, K4), the fiscal year ZCLFISCYR
"!   and the fiscal period ZCLFISCPR, both compounded with the variant. Each visit is booked under one variant, by its
"!   number; all three follow the calendar (the period is the month), so 2024001 exists under each
"!   (docs/bw-schema-design-guide.md, sections 3.7 and 3.8: a cube that fixes ZCLFISCVR = K4 has a third of the visits,
"!   its periods by their own key). They are the demo's own, not BW's 0FISC*, whose periods BW checks against the
"!   source system's fiscal year variants,
"! - the cube-type aDSO ZCLVISITA with the same visits and BW's standard time characteristics in place of the date,
"!   read through its fact view (the SID of the room, ZZXXMLA1_CL_BW_VIEW_GEN),
"! loads them and deploys per provider the schema the schema generator proposes (docs/schema-generator.md), accepted
"! through the schema API as the UI accepts it: the views generated (ZZXXMLA1_CL_BW_VIEW_GEN), the schema file written
"! and its catalog added to /WEB-INF/datasources.xml. A run deletes everything and creates the InfoCube, the aDSO or
"! both, as asked.
"! Every characteristic has language-dependent texts (short, medium and long) and the run loads EN texts for all its
"! values, so the views and BW's own front ends show a text next to every key.
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
    "! the test catalog of the InfoCube: the reference's schema reference/schema/ClinicBW.xml
    CONSTANTS c_test_catalog TYPE string VALUE `ZCLHIER`.
    CONSTANTS c_hierarchy_org  TYPE rshienm VALUE 'ZCLDOC_ORG'.
    CONSTANTS c_hierarchy_site TYPE rshienm VALUE 'ZCLDOC_SITE'.
    CONSTANTS c_hierarchy_diag TYPE rshienm VALUE 'ZCLDIAG_ICD'.
    CONSTANTS c_hierarchy_prg  TYPE rshienm VALUE 'ZCLPAT_PRG'.
    CONSTANTS c_hierarchy_serv TYPE rshienm VALUE 'ZCLSERV_CAT'.
    CONSTANTS c_hierarchy_loc  TYPE rshienm VALUE 'ZCLSERV_LOC'.

    "! Deletes everything and generates the InfoObjects with their master data and hierarchies, and the providers
    "! asked for with their data, schemas and catalogs; the log of the run.
    "! @parameter max_visits | at most this many visits, spread evenly over the days; 0: all of them
    "! @parameter cube | the InfoCube ZCLVISIT and its catalog
    "! @parameter adso | the aDSO ZCLVISITA and its catalog
    METHODS run
      IMPORTING max_visits    TYPE i DEFAULT 0
                cube          TYPE abap_bool DEFAULT abap_true
                adso          TYPE abap_bool DEFAULT abap_true
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    " BW's codes (type pools RS, RSD, RSDMD), as constants of this class
    CONSTANTS: BEGIN OF c_objvers,
                 active   TYPE c LENGTH 1 VALUE 'A',
                 modified TYPE c LENGTH 1 VALUE 'M',
               END OF c_objvers.
    CONSTANTS: BEGIN OF c_iobjtp,
                 charact   TYPE c LENGTH 3 VALUE 'CHA',
                 keyfigure TYPE c LENGTH 3 VALUE 'KYF',
               END OF c_iobjtp.
    CONSTANTS c_cubetype_basic TYPE c LENGTH 1 VALUE 'B'.
    CONSTANTS: BEGIN OF c_tabclass,
                 md   TYPE c LENGTH 1 VALUE 'M',
                 text TYPE c LENGTH 1 VALUE 'T',
               END OF c_tabclass.
    CONSTANTS c_first_day TYPE d VALUE '20240101'.
    CONSTANTS c_last_day  TYPE d VALUE '20251231'.
    CONSTANTS c_seed      TYPE int8 VALUE 20240101.
    CONSTANTS c_patients  TYPE i VALUE 2000.
    "! patients registered without a visit (some in the new region Coastal, which has no visits at all): the master data
    "! has members the providers do not use, as a shared BW characteristic has
    CONSTANTS c_registered TYPE i VALUE 300.
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
        compounding TYPE ty_t_iobjnm,
        "! with hierarchies; version dependent; the entire hierarchy time dependent; with intervals
        hierarchies   TYPE abap_bool,
        hie_versions  TYPE abap_bool,
        hie_timedep   TYPE abap_bool,
        hie_intervals TYPE abap_bool,
        auth_relevant TYPE abap_bool,
        "! the external characteristics whose values can be nodes of its hierarchies
        hie_external  TYPE ty_t_iobjnm,
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
      "! the master data of a characteristic: per row the values of the compounding, the key and the values of the
      "! attributes, in their order
      BEGIN OF ty_md,
        iobjnm      TYPE rsiobjnm,
        compounding TYPE ty_t_iobjnm,
        attributes  TYPE ty_t_iobjnm,
        rows       TYPE ty_t_row,
      END OF ty_md,
      ty_t_md TYPE STANDARD TABLE OF ty_md WITH EMPTY KEY.
    TYPES:
      "! the EN texts of a characteristic: per row the values of the compounding, the key, the short and the long text
      "! (the medium text is the long one, cut at 40)
      BEGIN OF ty_texts,
        iobjnm      TYPE rsiobjnm,
        compounding TYPE ty_t_iobjnm,
        rows        TYPE ty_t_row,
        "! the keys of the rows, joined by /
        seen        TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line,
      END OF ty_texts,
      ty_t_texts TYPE STANDARD TABLE OF ty_texts WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_text,
        short TYPE string,
        long  TYPE string,
      END OF ty_text.
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
      "! a node of a hierarchy: a text node (with a text), a value of the characteristic (its key, no text), a value of
      "! an external characteristic (iobjnm, named by its key as BW names it: the compounding first, each part at its
      "! full length) or an interval of values (from and to, named by from); a link node shows the subtree of the node
      "! of its name that is no link; parent_iobjnm the parent's InfoObject where two nodes of the parent's name differ
      "! by it (a text node and a site NORTH), else every node of that name is the parent (a duplicate node)
      BEGIN OF ty_hie_node,
        name          TYPE string,
        parent        TYPE string,
        parent_iobjnm TYPE rsiobjnm,
        text          TYPE string,
        iobjnm        TYPE rsiobjnm,
        link          TYPE abap_bool,
        from          TYPE string,
        to            TYPE string,
      END OF ty_hie_node,
      ty_t_hie_node TYPE STANDARD TABLE OF ty_hie_node WITH EMPTY KEY.
    TYPES:
      "! a physician below another node than by default (another department, a branch instead of the main campus)
      BEGIN OF ty_move,
        physician TYPE i,
        node      TYPE string,
      END OF ty_move,
      ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY.
    TYPES:
      "! a time slice of a version of a hierarchy of the physicians
      BEGIN OF ty_hierarchy,
        iobjnm   TYPE rsiobjnm,
        name     TYPE rshienm,
        version  TYPE rsversion,
        datefrom TYPE d,
        dateto   TYPE d,
        text     TYPE string,
        "! suppress the not-assigned node (REST_H)
        norest   TYPE abap_bool,
        nodes    TYPE ty_t_hie_node,
      END OF ty_hierarchy,
      ty_t_hierarchy TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    TYPES ty_t_htab TYPE rsndi_t_htabstr.
    TYPES ty_t_jtab TYPE rsndi_t_jtabstr.
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
      "! a service a visit is billed for, by a code of four digits whose first is its category
      BEGIN OF ty_service,
        code TYPE string,
        name TYPE string,
      END OF ty_service,
      ty_t_service TYPE STANDARD TABLE OF ty_service WITH EMPTY KEY.
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
      "! the site and the room of a visit; blank when no physician was assigned
      BEGIN OF ty_room,
        site TYPE string,
        room TYPE string,
      END OF ty_room.
    TYPES:
      "! BW's time characteristics of a day
      BEGIN OF ty_calendar,
        calday     TYPE d,
        calweek    TYPE n LENGTH 6,
        calmonth   TYPE n LENGTH 6,
        calquarter TYPE n LENGTH 5,
        calyear    TYPE n LENGTH 4,
      END OF ty_calendar.
    TYPES:
      "! the fiscal time of a visit: its fiscal year variant, the period and the year in it
      BEGIN OF ty_fiscal,
        fiscvarnt TYPE c LENGTH 2,
        fiscper   TYPE n LENGTH 7,
        fiscyear  TYPE n LENGTH 4,
      END OF ty_fiscal.

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
    "! Patients with the next ids; registered ones (made after the visits, so these stay as they are) may also live in
    "! the city of a region where nobody has visited yet.
    METHODS build_patients
      IMPORTING !count     TYPE i
                registered TYPE abap_bool DEFAULT abap_false.
    METHODS build_physicians.
    METHODS build_diagnoses.
    "! The time slices of the versions of ZCLDOC_ORG and ZCLDOC_SITE, ZCLDIAG_ICD, ZCLPAT_PRG, ZCLSERV_CAT and
    "! ZCLSERV_LOC.
    METHODS hierarchies RETURNING VALUE(result) TYPE ty_t_hierarchy.
    "! The nodes of a time slice of ZCLDOC_ORG: the text nodes and below its department every physician, moved ones
    "! elsewhere.
    METHODS organization
      IMPORTING text_nodes    TYPE ty_t_hie_node
                moves         TYPE ty_t_move OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! The nodes of a time slice of ZCLDOC_SITE: the text nodes and every physician below the main campus MAIN or the
    "! branch of a move.
    METHODS sites
      IMPORTING text_nodes    TYPE ty_t_hie_node
                moves         TYPE ty_t_move
      RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! Appends a node and its subtree to the hierarchy table (NDI format: parent, first child and next sibling).
    "! The nodes of ZCLDIAG_ICD: all diagnoses > chapter > group > diagnosis; the initial value (no diagnosis recorded)
    "! a leaf of its own chapter and group, so every value is assigned.
    METHODS diagnosis_nodes RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! The nodes of ZCLPAT_PRG: all care programs > area > program > patient; a program under a second parent is a link
    "! node, a patient in a second program a duplicate node or a link node; in family care a parent is a postable node
    "! with their children below them.
    METHODS care_program_nodes RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! The nodes of ZCLSERV_LOC: all locations > site (ZCLSITE) > room (ZCLROOM) > service, and the laboratories'
    "! services under text nodes, one of them NORTH next to the site NORTH; every service once.
    METHODS service_location_nodes RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! The nodes of ZCLSERV_CAT: all services > category > interval of codes, and care pathways with overlapping
    "! intervals, a linked category and a linked interval.
    METHODS service_catalog_nodes RETURNING VALUE(result) TYPE ty_t_hie_node.
    "! The services, by code.
    METHODS services RETURNING VALUE(result) TYPE ty_t_service.
    "! The service of a visit: by visit type, chapter of the diagnosis and age, its number choosing among a few.
    METHODS service IMPORTING visit TYPE ty_visit index TYPE i RETURNING VALUE(result) TYPE string.
    "! A text node's name for a text: upper case, a blank or hyphen as underscore, at most 32 characters.
    METHODS node_name IMPORTING text TYPE string RETURNING VALUE(result) TYPE string.
    METHODS add_node
      IMPORTING iobjnm   TYPE rsiobjnm
                nodes    TYPE ty_t_hie_node
                node     TYPE ty_hie_node
                parentid TYPE rshienodid
                tlevel   TYPE i
      CHANGING  htab     TYPE ty_t_htab
                jtab     TYPE ty_t_jtab.
    "! The departments a patient of each age group is sent to, with their weights.
    METHODS department_weights RETURNING VALUE(result) TYPE ty_t_group_weight.
    "! The diagnoses each department sees, with their weights.
    METHODS diagnosis_weights RETURNING VALUE(result) TYPE ty_t_group_weight.
    METHODS build_visits.
    "! Keeps max_visits of the visits, evenly spread, in their order.
    METHODS limit_visits IMPORTING max_visits TYPE i.
    METHODS master_data RETURNING VALUE(result) TYPE ty_t_md.
    "! The texts of every characteristic: of the keys of the master data, of the values of the attributes and of the
    "! fiscal time, whose SIDs come with the loads.
    METHODS texts RETURNING VALUE(result) TYPE ty_t_texts.
    "! The text of a value of an attribute characteristic (ZCLAGEGR 0-17: Children (0-17)).
    METHODS attribute_text
      IMPORTING iobjnm        TYPE rsiobjnm
                value         TYPE string
      RETURNING VALUE(result) TYPE ty_text.
    "! Appends a row of texts to the characteristic's entry; a blank key or one that is there already is left out.
    METHODS add_text
      IMPORTING iobjnm      TYPE rsiobjnm
                compounding TYPE ty_t_iobjnm OPTIONAL
                keys        TYPE string_table
                text        TYPE ty_text
      CHANGING  texts       TYPE ty_t_texts.
    METHODS month_name IMPORTING month TYPE i RETURNING VALUE(result) TYPE string.
    METHODS day_name IMPORTING day TYPE d RETURNING VALUE(result) TYPE string.
    "! Monday, 1 January 2024
    METHODS long_date IMPORTING day TYPE d RETURNING VALUE(result) TYPE string.
    METHODS calendar IMPORTING day TYPE d RETURNING VALUE(result) TYPE ty_calendar.
    "! The site and room of a visit, from its physician and patient: no random number, so the visits stay as they were.
    METHODS room IMPORTING visit TYPE ty_visit RETURNING VALUE(result) TYPE ty_room.
    "! The fiscal time of a visit: the variant by the visit's number (K1, K2, K4 in turn), the period and the year of
    "! the calendar, as all three follow it.
    METHODS fiscal IMPORTING visit TYPE ty_visit index TYPE i RETURNING VALUE(result) TYPE ty_fiscal.

    METHODS delete_all.
    METHODS delete_cube.
    METHODS delete_adso.
    METHODS delete_views.
    METHODS delete_hierarchies.
    "! Deletes the copies of the characteristics' hierarchies and their objects, which BW's deletion trips over.
    METHODS delete_hierarchy_copies.
    METHODS delete_infoobjects.
    METHODS ensure_infoarea.
    METHODS create_characteristic IMPORTING cha TYPE ty_cha.
    METHODS create_key_figure IMPORTING kyf TYPE ty_kyf.
    METHODS activate_infoobjects.
    METHODS create_cube.
    METHODS activate_cube.
    METHODS load_master_data IMPORTING md TYPE ty_md.
    "! Writes the EN texts into the characteristic's text table (/BIC/T...).
    METHODS load_texts IMPORTING texts TYPE ty_texts.
    "! Saves and activates a time slice of a hierarchy (RSNDI_SHIE_STRUCTURE_UPDATE4, RSNDI_SHIE_ACTIVATE; UPDATE3
    "! dumps on the 2025 system: CL_RSSH_HIERARCHY_FUNC=>NDI_UPDATE no longer takes its table of hierarchy texts).
    METHODS load_hierarchy IMPORTING hierarchy TYPE ty_hierarchy.
    METHODS load_cube.
    METHODS create_adso.
    "! The name BW generated for a table or view of the aDSO (CL_RSO_ADSO=>GET_TABLNM).
    METHODS adso_table IMPORTING type TYPE rsdsotabtype RETURNING VALUE(result) TYPE tabname.
    METHODS load_adso.
    "! Counts the rows of a fact table or view and sums the duration.
    METHODS verify IMPORTING source TYPE csequence.

    "! Per provider the schema the proposal makes (as GET proposal of the schema API: the fiscal defaults, then the
    "! proposal), accepted as the UI accepts it (POST accept: the views generated, the schema file written, the catalog
    "! added).
    METHODS deploy_schemas
      IMPORTING providers TYPE string_table.
    "! Adds to the schema of a provider every BW hierarchy BW has for the characteristic of one of its dimensions and
    "! olap4abap serves (ZZXXMLA1_CL_BW_HIERARCHY_COPY=>offered), as the user ticks them in the schema builder
    "! (ZCLDIAG_ICD, ZCLPAT_PRG, ZCLSERV_CAT, ZCLSERV_LOC and per version ZCLDOC_ORG and ZCLDOC_SITE, their slices valid
    "! to 9999-12-31: ZCLDOC_ORG_001, ..., on ZCLVISIT and ZCLVISITA).
    METHODS tick_hierarchies
      CHANGING !schema TYPE zzxxmla1_cl_schema_def=>ty_schema.
    "! The test catalog ZCLHIER from the InfoCube's schema: the reference's reference/schema/ClinicBW.xml, catalog and
    "! cube named ZCLHIER, with the BW hierarchies (olap4abap's form, no reference case names but ZCLDIAG_ICD) and
    "! without olap4abap's extensions (membersWithFacts, omitEmptyCells), so its answers are the reference's
    "! (scripts/xmla_test.py, the *_hier* cases; scripts/ssas_compare.py).
    METHODS test_schema
      IMPORTING !schema       TYPE zzxxmla1_cl_schema_def=>ty_schema
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_def=>ty_schema.
    "! The annotations but olap4abap's extensions membersWithFacts and omitEmptyCells, as a new object; none left: unbound.
    METHODS without_extensions
      IMPORTING annotations   TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_schema_def=>ty_annotations.
    "! The proposal for a provider.
    METHODS propose
      IMPORTING provider      TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_cl_schema_def=>ty_schema
      RAISING   zzxxmla1_cx_bw_provider
                zzxxmla1_cx_xom.
    "! Accepts a schema into a catalog through the schema API.
    METHODS accept
      IMPORTING catalog TYPE csequence
                !schema TYPE zzxxmla1_cl_schema_def=>ty_schema.
    "! Removes the catalogs of the demo's schemas (and their files and views) through the schema API, so that accept
    "! checks no catalog on the views a run deletes; also those a run did not create (one provider only, or K4).
    METHODS remove_catalogs.

    "! The field of an InfoObject in BW's generated tables (RSD_FIELDNM_GET_FROM_IOBJNM), checked against the structure;
    "! without namespace: as a fact view names it.
    METHODS iobj_field
      IMPORTING struct            TYPE REF TO cl_abap_structdescr
                iobjnm            TYPE rsiobjnm
                without_namespace TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result)     TYPE string.
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
    CLEAR patients.
    build_patients( c_patients ).
    build_physicians( ).
    build_diagnoses( ).
    build_visits( ).
    build_patients( count = c_registered registered = abap_true ).
    limit_visits( max_visits ).
    write( |{ lines( patients ) } patients ({ c_registered } without visits), { lines( physicians ) } physicians, | &&
           |{ lines( diagnoses ) } diagnoses, { lines( visits ) } visits| ).

    delete_all( ).
    ensure_infoarea( ).
    LOOP AT characteristics( ) INTO DATA(cha).
      create_characteristic( cha ).
    ENDLOOP.
    LOOP AT key_figures( ) INTO DATA(kyf).
      create_key_figure( kyf ).
    ENDLOOP.
    activate_infoobjects( ).
    IF cube = abap_true.
      create_cube( ).
      activate_cube( ).
    ENDIF.
    LOOP AT master_data( ) INTO DATA(md).
      load_master_data( md ).
    ENDLOOP.
    " after the attributes: the rooms' SIDs follow the order of their master data load
    LOOP AT texts( ) INTO DATA(texts).
      load_texts( texts ).
    ENDLOOP.
    LOOP AT hierarchies( ) INTO DATA(hierarchy).
      load_hierarchy( hierarchy ).
    ENDLOOP.
    DATA providers TYPE string_table.
    IF cube = abap_true.
      load_cube( ).
      verify( |/BIC/F{ c_cube }| ).
      APPEND CONV #( c_cube ) TO providers.
    ENDIF.
    IF adso = abap_true.
      create_adso( ).
      load_adso( ).
      verify( adso_table( cl_rsdso_constants=>n_c_viewtype_reporting ) ).
      APPEND CONV #( c_adso ) TO providers.
    ENDIF.

    deploy_schemas( providers ).
    result = log.
  ENDMETHOD.

  METHOD write.
    APPEND text TO log.
  ENDMETHOD.

  METHOD characteristics.
    " attributes first: the dimension characteristics reference them; NUMC values are named as BW holds them (2025, 01)
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
      ( name = 'ZCLRTYPE' text = 'Room Type'         leng = 20 )
      " the fiscal year variant before the period and year compounded with it
      ( name = 'ZCLFISCVR' text = 'Fiscal Year Variant' leng = 2 )
      ( name = 'ZCLFISCYR' text = 'Fiscal Year'   datatp = 'NUMC' leng = 4 compounding = VALUE #( ( 'ZCLFISCVR' ) ) )
      ( name = 'ZCLFISCPR' text = 'Fiscal Period' datatp = 'NUMC' leng = 7 compounding = VALUE #( ( 'ZCLFISCVR' ) ) )
      " the site before the room compounded with it
      ( name = 'ZCLSITE'  text = 'Site'       leng = 10
        attributes = VALUE #( ( 'ZCLCITY' ) ) )
      ( name = 'ZCLROOM'  text = 'Room'       leng = 4
        compounding = VALUE #( ( 'ZCLSITE' ) ) attributes = VALUE #( ( 'ZCLRTYPE' ) ) )
      " the dimension characteristics
      ( name = 'ZCLPAT'   text = 'Patient'    datatp = 'NUMC' leng = 6
        attributes = VALUE #( ( 'ZCLPNAME' ) ( 'ZCLSEX' ) ( 'ZCLBYEAR' ) ( 'ZCLAGEGR' ) ( 'ZCLBLOOD' ) ( 'ZCLINSUR' )
                              ( 'ZCLCITY' ) ( 'ZCLREGIO' ) )
        hierarchies = abap_true )
      ( name = 'ZCLDOC'   text = 'Physician'  datatp = 'NUMC' leng = 3
        attributes = VALUE #( ( 'ZCLDNAME' ) ( 'ZCLDEPT' ) ( 'ZCLEXPER' ) )
        hierarchies = abap_true hie_versions = abap_true hie_timedep = abap_true auth_relevant = abap_true )
      ( name = 'ZCLDIAG'  text = 'Diagnosis'  leng = 5
        attributes = VALUE #( ( 'ZCLDTEXT' ) ( 'ZCLDGRP' ) ( 'ZCLDCHAP' ) )
        hierarchies = abap_true auth_relevant = abap_true )
      ( name = 'ZCLVTYPE' text = 'Visit Type' leng = 20
        attributes = VALUE #( ( 'ZCLSETNG' ) ) )
      ( name = 'ZCLSERV'  text = 'Service'    datatp = 'NUMC' leng = 4
        attributes = VALUE #( ( 'ZCLSETNG' ) ) hierarchies = abap_true hie_intervals = abap_true
        hie_external = VALUE #( ( 'ZCLSITE' ) ( 'ZCLROOM' ) ) )
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
      ( suffix = '5' text = 'Time'       iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLDATE' ) ) )
      ( suffix = '6' text = 'Room'       iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLSITE' ) ( 'ZCLROOM' ) ) )
      ( suffix = '7' text = 'Fiscal Time' iobjtp = 'CHA'
        iobjnms = VALUE #( ( 'ZCLFISCVR' ) ( 'ZCLFISCYR' ) ( 'ZCLFISCPR' ) ) )
      ( suffix = '8' text = 'Service'    iobjtp = 'CHA' iobjnms = VALUE #( ( 'ZCLSERV' ) ) ) ).
  ENDMETHOD.

  METHOD all_iobjnm.
    result = VALUE #( FOR c IN characteristics( ) ( c-name ) ).
    APPEND LINES OF VALUE ty_t_iobjnm( FOR k IN key_figures( ) ( k-name ) ) TO result.
  ENDMETHOD.

  METHOD dimension_characteristics.
    result = VALUE #( ( 'ZCLPAT' ) ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ( 'ZCLVTYPE' ) ( 'ZCLDATE' ) ( 'ZCLSITE' ) ( 'ZCLROOM' )
                      ( 'ZCLFISCVR' ) ( 'ZCLFISCYR' ) ( 'ZCLFISCPR' ) ( 'ZCLSERV' ) ).
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
    IF registered = abap_true.
      APPEND VALUE #( scope = `Coastal` key = `Kingsport` ) TO cities.
    ENDIF.
    DATA(age_groups) = VALUE ty_t_weight( ( key = `0-17` weight = 20 ) ( key = `18-39` weight = 27 )
                                          ( key = `40-64` weight = 30 ) ( key = `65+` weight = 23 ) ).
    DATA(blood_groups) = VALUE ty_t_weight( ( key = `O+` weight = 37 ) ( key = `A+` weight = 34 )
                                            ( key = `B+` weight = 9 ) ( key = `AB+` weight = 4 )
                                            ( key = `O-` weight = 7 ) ( key = `A-` weight = 6 )
                                            ( key = `B-` weight = 2 ) ( key = `AB-` weight = 1 ) ).
    DATA(insurances) = VALUE ty_t_weight( ( key = `Statutory` weight = 75 ) ( key = `Private` weight = 20 )
                                          ( key = `Self-pay` weight = 5 ) ).
    DATA(first_id) = lines( patients ) + 1.
    DO count TIMES.
      DATA(patient) = VALUE ty_patient( id = first_id + sy-index - 1 ).
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
      moves = VALUE #( ( physician = 8 node = `GP` ) ( physician = 11 node = `EMER` ) ) ).
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
    " The sites: in 2024 the main campus in the city center and the Riverside branch in the suburbs. On 1 January 2025
    " the Northgate branch opens in the suburbs with physicians from both (version 001); the plan (version 002) had put
    " it in the city center, with other physicians. A physician's site and department are independent, so a restriction
    " on a node of one hierarchy cuts across the nodes of the other.
    DATA(sites_2024) = sites(
      text_nodes = VALUE #(
        ( name = `SITES` text = `All Sites` )
        ( name = `CITY`    parent = `SITES`   text = `City Center` )
        ( name = `SUBURBS` parent = `SITES`   text = `Suburbs` )
        ( name = `MAIN`    parent = `CITY`    text = `Main Campus` )
        ( name = `RIVER`   parent = `SUBURBS` text = `Riverside Branch` ) )
      moves = VALUE #( node = `RIVER` ( physician = 4 ) ( physician = 5 ) ( physician = 8 ) ( physician = 11 )
                                      ( physician = 13 ) ( physician = 16 ) ( physician = 18 ) ) ).
    DATA(sites_actual_2025) = sites(
      text_nodes = VALUE #(
        ( name = `SITES` text = `All Sites` )
        ( name = `CITY`    parent = `SITES`   text = `City Center` )
        ( name = `SUBURBS` parent = `SITES`   text = `Suburbs` )
        ( name = `MAIN`    parent = `CITY`    text = `Main Campus` )
        ( name = `RIVER`   parent = `SUBURBS` text = `Riverside Branch` )
        ( name = `NORTH`   parent = `SUBURBS` text = `Northgate Branch` ) )
      moves = VALUE #( ( physician = 4 node = `RIVER` ) ( physician = 11 node = `RIVER` )
                       ( physician = 13 node = `RIVER` ) ( physician = 18 node = `RIVER` )
                       ( physician = 2 node = `NORTH` ) ( physician = 5 node = `NORTH` )
                       ( physician = 8 node = `NORTH` ) ( physician = 16 node = `NORTH` ) ) ).
    DATA(sites_plan_2025) = sites(
      text_nodes = VALUE #(
        ( name = `SITES` text = `All Sites` )
        ( name = `CITY`    parent = `SITES`   text = `City Center` )
        ( name = `SUBURBS` parent = `SITES`   text = `Suburbs` )
        ( name = `MAIN`    parent = `CITY`    text = `Main Campus` )
        ( name = `NORTH`   parent = `CITY`    text = `Northgate Branch` )
        ( name = `RIVER`   parent = `SUBURBS` text = `Riverside Branch` ) )
      moves = VALUE #( ( physician = 5 node = `RIVER` ) ( physician = 8 node = `RIVER` )
                       ( physician = 11 node = `RIVER` ) ( physician = 16 node = `RIVER` )
                       ( physician = 3 node = `NORTH` ) ( physician = 4 node = `NORTH` )
                       ( physician = 13 node = `NORTH` ) ( physician = 18 node = `NORTH` ) ) ).
    result = VALUE #( iobjnm = 'ZCLDOC'
      ( name = c_hierarchy_org version = '001' datefrom = '10000101' dateto = '20241231' text = `Clinic Organization`
        nodes = slice_2024 )
      ( name = c_hierarchy_org version = '001' datefrom = '20250101' dateto = '99991231' text = `Clinic Organization`
        nodes = actual_2025 )
      ( name = c_hierarchy_org version = '002' datefrom = '10000101' dateto = '20241231'
        text = `Clinic Organization (Plan)` nodes = slice_2024 )
      ( name = c_hierarchy_org version = '002' datefrom = '20250101' dateto = '99991231'
        text = `Clinic Organization (Plan)` nodes = plan_2025 )
      ( name = c_hierarchy_site version = '001' datefrom = '10000101' dateto = '20241231' text = `Clinic Sites`
        nodes = sites_2024 )
      ( name = c_hierarchy_site version = '001' datefrom = '20250101' dateto = '99991231' text = `Clinic Sites`
        nodes = sites_actual_2025 )
      ( name = c_hierarchy_site version = '002' datefrom = '10000101' dateto = '20241231'
        text = `Clinic Sites (Plan)` nodes = sites_2024 )
      ( name = c_hierarchy_site version = '002' datefrom = '20250101' dateto = '99991231'
        text = `Clinic Sites (Plan)` nodes = sites_plan_2025 ) ).
    " the diagnoses in a plain hierarchy, neither version nor time dependent; every value is in it, the not-assigned
    " node suppressed
    APPEND VALUE #( iobjnm = 'ZCLDIAG' name = c_hierarchy_diag dateto = '99991231' text = `Diagnoses by ICD-10 Chapter`
                    norest = abap_true nodes = diagnosis_nodes( ) ) TO result.
    " the patients' care programs, plain too, with link nodes
    APPEND VALUE #( iobjnm = 'ZCLPAT' name = c_hierarchy_prg dateto = '99991231' text = `Care Programs`
                    nodes = care_program_nodes( ) ) TO result.
    " the services by intervals of their codes, plain too
    APPEND VALUE #( iobjnm = 'ZCLSERV' name = c_hierarchy_serv dateto = '99991231' text = `Service Catalog`
                    nodes = service_catalog_nodes( ) ) TO result.
    " the services by where they are given, nodes of the sites and rooms (external characteristics), plain too
    APPEND VALUE #( iobjnm = 'ZCLSERV' name = c_hierarchy_loc dateto = '99991231' text = `Service Locations`
                    nodes = service_location_nodes( ) ) TO result.
  ENDMETHOD.

  METHOD service_location_nodes.
    " A room is named by BW's key of ZCLROOM: the site (ZCLSITE, CHAR 10) at its full length, then the room. The
    " rooms follow their type (master_data): consultations and mental health in consultation rooms, therapy, prevention
    " and emergency care in treatment rooms, imaging and functional tests in the imaging room; the laboratory is no
    " room of the clinic, so its services are under text nodes: the external laboratory's and the rapid tests and
    " cultures of a partner laboratory, the text node NORTH next to the site NORTH (BW keys a node by InfoObject and
    " name, so the two are siblings; their unique names differ by the InfoObject). No service is in two places.
    DATA(rooms) = VALUE string_table(
      ( `NORTH R01 1001 1005` ) ( `NORTH R02 5001 5003` ) ( `NORTH R03 3001 3007` ) ( `NORTH R04 3051 3055` )
      ( `NORTH R05 2101 2206` ) ( `SOUTH R01 4001 4007` ) ( `SOUTH R02 1010 1012` ) ).
    DATA(catalog) = services( ).
    result = VALUE #( ( name = `LOCATIONS` text = `All Locations` )
                      ( name = `NORTH` parent = `LOCATIONS` iobjnm = 'ZCLSITE' )
                      ( name = `SOUTH` parent = `LOCATIONS` iobjnm = 'ZCLSITE' ) ).
    LOOP AT rooms INTO DATA(room).
      SPLIT room AT ` ` INTO DATA(site) DATA(number) DATA(first) DATA(last).
      DATA(key) = |{ site WIDTH = 10 }{ number }|.
      APPEND VALUE #( name = key parent = site parent_iobjnm = 'ZCLSITE' iobjnm = 'ZCLROOM' ) TO result.
      LOOP AT catalog INTO DATA(service) WHERE code BETWEEN first AND last.
        APPEND VALUE #( name = service-code parent = key ) TO result.
      ENDLOOP.
    ENDLOOP.
    APPEND VALUE #( name = `LAB` parent = `LOCATIONS` text = `External Laboratory` ) TO result.
    LOOP AT catalog INTO service WHERE code BETWEEN `2001` AND `2007`.
      APPEND VALUE #( name = service-code parent = `LAB` ) TO result.
    ENDLOOP.
    APPEND VALUE #( name = `NORTH` parent = `LOCATIONS` text = `North Partner Laboratory` ) TO result.
    LOOP AT catalog INTO service WHERE code BETWEEN `2008` AND `2099`.
      APPEND VALUE #( name = service-code parent = `NORTH` parent_iobjnm = '0HIER_NODE' ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD service_catalog_nodes.
    " Every category is an interval of codes, so a service is under its category by its code alone. The care pathways
    " take services again: the emergency pathway an interval within the consultations' (overlapping intervals under
    " different parents are duplicate nodes), imaging as a link node with its interval below it and the minor
    " procedures' interval as a link node; the cardiac pathway an interval within the laboratory's and the functional
    " tests as a link node.
    result = VALUE #(
      ( name = `SERVICES` text = `All Services` )
      ( name = `CONSULT`     parent = `SERVICES`    text = `Consultations` )
      ( name = `1000`        parent = `CONSULT`     from = `1000` to = `1099` )
      ( name = `DIAGNOSTICS` parent = `SERVICES`    text = `Diagnostics` )
      ( name = `LAB`         parent = `DIAGNOSTICS` text = `Laboratory` )
      ( name = `2000`        parent = `LAB`         from = `2000` to = `2099` )
      ( name = `IMAGING`     parent = `DIAGNOSTICS` text = `Imaging` )
      ( name = `2100`        parent = `IMAGING`     from = `2100` to = `2199` )
      ( name = `FUNCTION`    parent = `DIAGNOSTICS` text = `Functional Tests` )
      ( name = `2200`        parent = `FUNCTION`    from = `2200` to = `2299` )
      ( name = `THERAPY`     parent = `SERVICES`    text = `Therapy` )
      ( name = `3000`        parent = `THERAPY`     from = `3000` to = `3049` )
      ( name = `3050`        parent = `THERAPY`     from = `3050` to = `3099` )
      ( name = `PREVENTION`  parent = `SERVICES`    text = `Prevention` )
      ( name = `4000`        parent = `PREVENTION`  from = `4000` to = `4099` )
      ( name = `MENTAL`      parent = `SERVICES`    text = `Mental Health` )
      ( name = `5000`        parent = `MENTAL`      from = `5000` to = `5099` )
      ( name = `PATHWAYS`    parent = `SERVICES`    text = `Care Pathways` )
      ( name = `EMERGENCY`   parent = `PATHWAYS`    text = `Emergency Pathway` )
      ( name = `1010`        parent = `EMERGENCY`   from = `1010` to = `1019` )
      ( name = `IMAGING`     parent = `EMERGENCY`   text = `Imaging` link = abap_true )
      ( name = `3000`        parent = `EMERGENCY`   from = `3000` to = `3049` link = abap_true )
      ( name = `CARDIAC`     parent = `PATHWAYS`    text = `Cardiac Pathway` )
      ( name = `2003`        parent = `CARDIAC`     from = `2003` to = `2004` )
      ( name = `FUNCTION`    parent = `CARDIAC`     text = `Functional Tests` link = abap_true ) ).
  ENDMETHOD.

  METHOD services.
    result = VALUE #(
      ( code = `1001` name = `Initial Consultation` )
      ( code = `1002` name = `Follow-up Consultation` )
      ( code = `1003` name = `Extended Consultation` )
      ( code = `1004` name = `Telehealth Consultation` )
      ( code = `1005` name = `Telehealth Follow-up` )
      ( code = `1010` name = `Emergency Assessment` )
      ( code = `1011` name = `Emergency Treatment` )
      ( code = `1012` name = `Emergency Observation` )
      ( code = `2001` name = `Complete Blood Count` )
      ( code = `2002` name = `Metabolic Panel` )
      ( code = `2003` name = `Lipid Panel` )
      ( code = `2004` name = `HbA1c Test` )
      ( code = `2005` name = `Thyroid Panel` )
      ( code = `2006` name = `Urinalysis` )
      ( code = `2007` name = `C-Reactive Protein` )
      ( code = `2008` name = `Rapid Influenza Test` )
      ( code = `2009` name = `Rapid Strep Test` )
      ( code = `2010` name = `Bacterial Culture` )
      ( code = `2101` name = `Chest X-Ray` )
      ( code = `2102` name = `Limb X-Ray` )
      ( code = `2103` name = `Spine X-Ray` )
      ( code = `2104` name = `Ultrasound` )
      ( code = `2105` name = `Head CT` )
      ( code = `2106` name = `MRI` )
      ( code = `2201` name = `ECG` )
      ( code = `2202` name = `Stress ECG` )
      ( code = `2203` name = `Echocardiography` )
      ( code = `2204` name = `Spirometry` )
      ( code = `2205` name = `Pulse Oximetry` )
      ( code = `2206` name = `Holter Monitoring` )
      ( code = `3001` name = `Wound Care` )
      ( code = `3002` name = `Suturing` )
      ( code = `3003` name = `Splinting` )
      ( code = `3004` name = `Cast Application` )
      ( code = `3005` name = `Skin Biopsy` )
      ( code = `3006` name = `Cryotherapy` )
      ( code = `3007` name = `Lesion Excision` )
      ( code = `3051` name = `Joint Injection` )
      ( code = `3052` name = `Physiotherapy Session` )
      ( code = `3053` name = `Inhalation Therapy` )
      ( code = `3054` name = `Infusion` )
      ( code = `3055` name = `Intramuscular Injection` )
      ( code = `4001` name = `Influenza Vaccination` )
      ( code = `4002` name = `Tetanus Vaccination` )
      ( code = `4003` name = `Childhood Vaccination` )
      ( code = `4004` name = `Adult Check-up` )
      ( code = `4005` name = `Child Check-up` )
      ( code = `4006` name = `Cancer Screening` )
      ( code = `4007` name = `Lifestyle Counselling` )
      ( code = `5001` name = `Psychotherapy Session` )
      ( code = `5002` name = `Psychiatric Assessment` )
      ( code = `5003` name = `Crisis Intervention` ) ).
  ENDMETHOD.

  METHOD service.
    " no random draw, so the visits stay as they were; some services have no visit (master data without facts)
    DATA(chapter) = VALUE string( diagnoses[ code = visit-diagnosis ]-chapter OPTIONAL ).
    DATA(child) = xsdbool( visit-patient > 0 AND patients[ visit-patient ]-age_group = `0-17` ).
    DATA(choices) = COND string_table(
      WHEN visit-visit_type = `Telehealth` THEN VALUE #( ( `1004` ) ( `1004` ) ( `1005` ) )
      WHEN visit-visit_type = `Emergency` THEN SWITCH #( chapter
        WHEN `Injuries`      THEN VALUE #( ( `2102` ) ( `3002` ) ( `3003` ) )
        WHEN `Circulatory`   THEN VALUE #( ( `2201` ) ( `1011` ) ( `2001` ) )
        WHEN `Respiratory`   THEN VALUE #( ( `2101` ) ( `1011` ) ( `2205` ) )
        WHEN `Mental health` THEN VALUE #( ( `5003` ) )
        ELSE VALUE #( ( `1010` ) ( `1011` ) ( `1012` ) ) )
      WHEN visit-visit_type = `Follow-up` THEN SWITCH #( chapter
        WHEN `Endocrine and metabolic` THEN VALUE #( ( `2004` ) ( `2002` ) ( `1002` ) )
        WHEN `Circulatory`   THEN VALUE #( ( `2003` ) ( `2201` ) ( `1002` ) )
        WHEN `Mental health` THEN VALUE #( ( `5001` ) )
        ELSE VALUE #( ( `1002` ) ) )
      ELSE SWITCH #( chapter
        WHEN `Respiratory`   THEN VALUE #( ( `2008` ) ( `2204` ) ( `1001` ) )
        WHEN `Circulatory`   THEN VALUE #( ( `2201` ) ( `2203` ) ( `2202` ) )
        WHEN `Endocrine and metabolic` THEN VALUE #( ( `2004` ) ( `2005` ) ( `2002` ) )
        WHEN `Musculoskeletal` THEN VALUE #( ( `2103` ) ( `3051` ) ( `3052` ) )
        WHEN `Skin`          THEN VALUE #( ( `3005` ) ( `3006` ) ( `3007` ) )
        WHEN `Infections`    THEN VALUE #( ( `2007` ) ( `2010` ) ( `2009` ) )
        WHEN `Injuries`      THEN VALUE #( ( `2102` ) ( `3001` ) ( `3004` ) )
        WHEN `Mental health` THEN VALUE #( ( `5002` ) ( `5001` ) ( `1003` ) )
        WHEN `Check-ups`     THEN COND #( WHEN child = abap_true THEN VALUE #( ( `4005` ) ( `4003` ) )
                                          ELSE VALUE #( ( `4004` ) ( `4001` ) ( `4006` ) ) )
        ELSE VALUE #( ( `1001` ) ) ) ).
    result = choices[ index MOD lines( choices ) + 1 ].
  ENDMETHOD.

  METHOD care_program_nodes.
    " The heart program is under chronic care and under senior care, and senior care under prevention too: link nodes,
    " whose subtree is their original's, so the heart program's patients are in the hierarchy three times, a link node
    " in a linked subtree. A patient in two programs is a leaf in both: a duplicate node (BW takes a value more than
    " once), in fall prevention a link node if the patient is in the heart program too.
    result = VALUE #(
      ( name = `PROGRAMS` text = `All Care Programs` )
      ( name = `CHRONIC`     parent = `PROGRAMS`   text = `Chronic Care` )
      ( name = `DIABETES`    parent = `CHRONIC`    text = `Diabetes Program` )
      ( name = `HEART`       parent = `CHRONIC`    text = `Heart Program` )
      ( name = `RESPIRATORY` parent = `CHRONIC`    text = `Respiratory Program` )
      ( name = `SENIOR`      parent = `PROGRAMS`   text = `Senior Care` )
      ( name = `HEART`       parent = `SENIOR`     text = `Heart Program` link = abap_true )
      ( name = `FALLS`       parent = `SENIOR`     text = `Fall Prevention` )
      ( name = `PREVENTION`  parent = `PROGRAMS`   text = `Prevention` )
      ( name = `SENIOR`      parent = `PREVENTION` text = `Senior Care` link = abap_true )
      ( name = `CHILD`       parent = `PREVENTION` text = `Child Health` )
      ( name = `FAMILY`      parent = `PREVENTION` text = `Family Care` ) ).
    " By age group and number, no random draw (the visits stay as they were); the patients without a visit too. Most
    " patients are in no program (BW's not assigned).
    LOOP AT patients INTO DATA(patient).
      DATA(adult) = xsdbool( patient-age_group = `40-64` OR patient-age_group = `65+` ).
      DATA(senior) = xsdbool( patient-age_group = `65+` ).
      DATA(programs) = VALUE string_table(
        ( COND #( WHEN adult = abap_true AND patient-id MOD 9 = 0 THEN `DIABETES` ) )
        ( COND #( WHEN senior = abap_true AND patient-id MOD 4 = 0
                    OR patient-age_group = `40-64` AND patient-id MOD 12 = 0 THEN `HEART` ) )
        ( COND #( WHEN adult = abap_true AND patient-id MOD 10 = 4 THEN `RESPIRATORY` ) )
        ( COND #( WHEN senior = abap_true AND patient-id MOD 6 = 0 THEN `FALLS` ) )
        ( COND #( WHEN patient-age_group = `0-17` AND patient-id MOD 5 = 0 THEN `CHILD` ) ) ).
      LOOP AT programs INTO DATA(program) WHERE table_line IS NOT INITIAL.
        APPEND VALUE #( name   = |{ patient-id WIDTH = 6 ALIGN = RIGHT PAD = '0' }|
                        parent = program
                        link   = xsdbool( program = `FALLS` AND line_exists( programs[ table_line = `HEART` ] ) ) )
               TO result.
      ENDLOOP.
    ENDLOOP.
    " Family care: a parent and below them up to three children of the same city among the next 40 patients, so the
    " parent is a postable node (a value with children and visits of its own). Parents are 18 to 39, in no other
    " program, so a postable node is in the hierarchy once; a child in child health too is a duplicate leaf.
    LOOP AT patients INTO DATA(guardian) WHERE age_group = `18-39`.
      IF guardian-id MOD 50 <> 7.
        CONTINUE.
      ENDIF.
      DATA(last) = guardian-id + 40.
      DATA(children) = VALUE ty_t_patient( FOR c IN patients WHERE ( age_group = `0-17` AND city = guardian-city
                                                                     AND id > guardian-id AND id <= last ) ( c ) ).
      IF children IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(guardian_key) = |{ guardian-id WIDTH = 6 ALIGN = RIGHT PAD = '0' }|.
      APPEND VALUE #( name = guardian_key parent = `FAMILY` ) TO result.
      LOOP AT children INTO DATA(child) TO 3.
        APPEND VALUE #( name = |{ child-id WIDTH = 6 ALIGN = RIGHT PAD = '0' }| parent = guardian_key ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD diagnosis_nodes.
    result = VALUE #( ( name = `DIAGNOSES` text = `All Diagnoses` ) ).
    LOOP AT diagnoses INTO DATA(diagnosis).
      DATA(chapter) = node_name( diagnosis-chapter ).
      DATA(group) = node_name( diagnosis-diagnosis_group ).
      IF NOT line_exists( result[ name = chapter ] ).
        APPEND VALUE #( name = chapter parent = `DIAGNOSES` text = diagnosis-chapter ) TO result.
      ENDIF.
      IF NOT line_exists( result[ name = group ] ).
        APPEND VALUE #( name = group parent = chapter text = diagnosis-diagnosis_group ) TO result.
      ENDIF.
      APPEND VALUE #( name = diagnosis-code parent = group ) TO result.
    ENDLOOP.
    APPEND VALUE #( name = `NOT_RECORDED` parent = `DIAGNOSES` text = `Not recorded` ) TO result.
    APPEND VALUE #( name = `NO_DIAGNOSIS` parent = `NOT_RECORDED` text = `No diagnosis` ) TO result.
    APPEND VALUE #( name = `` parent = `NO_DIAGNOSIS` ) TO result.
  ENDMETHOD.

  METHOD node_name.
    result = to_upper( translate( val = text from = ` -` to = `__` ) ).
    IF strlen( result ) > 32.
      result = result(32).
    ENDIF.
  ENDMETHOD.

  METHOD sites.
    result = text_nodes.
    LOOP AT physicians INTO DATA(physician).
      DATA(site) = VALUE string( moves[ physician = physician-id ]-node DEFAULT `MAIN` ).
      APPEND VALUE #( name = |{ physician-id WIDTH = 3 ALIGN = RIGHT PAD = '0' }| parent = site ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD organization.
    result = text_nodes.
    LOOP AT physicians INTO DATA(physician).
      DATA(department) = VALUE string( moves[ physician = physician-id ]-node OPTIONAL ).
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
    DATA(node_iobjnm) = COND rsiobjnm( WHEN node-iobjnm IS NOT INITIAL THEN node-iobjnm
                                       WHEN node-text IS INITIAL THEN iobjnm
                                       ELSE '0HIER_NODE' ).
    APPEND VALUE #( nodeid   = nodeid
                    iobjnm   = node_iobjnm
                    nodename = node-name
                    tlevel   = tlevel
                    link     = node-link
                    intervl  = xsdbool( node-to IS NOT INITIAL )
                    parentid = parentid ) TO htab.
    IF node-to IS NOT INITIAL.
      APPEND VALUE #( nodeid = nodeid leaffrom = node-from leafto = node-to ) TO jtab.
    ENDIF.
    " BW shows a link node's original's subtree below it: it has no children of its own; the initial value is a leaf
    " (its empty name is the root's parent)
    IF node-link = abap_true OR node-name IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT nodes INTO DATA(child) WHERE parent = node-name
                                     AND ( parent_iobjnm IS INITIAL OR parent_iobjnm = node_iobjnm ).
      DATA(childid) = CONV rshienodid( lines( htab ) + 1 ).
      IF previous IS INITIAL.
        htab[ nodeid ]-childid = childid.
      ELSE.
        htab[ previous ]-nextid = childid.
      ENDIF.
      add_node( EXPORTING iobjnm   = iobjnm
                          nodes    = nodes
                          node     = child
                          parentid = nodeid
                          tlevel   = tlevel + 1
                CHANGING  htab     = htab
                          jtab     = jtab ).
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
    DATA date_rows TYPE ty_t_row.
    DATA(day) = c_first_day.
    WHILE day <= c_last_day.
      DATA(month) = CONV i( day+4(2) ).
      DATA(january) = CONV d( |{ day(4) }0101| ).
      " weeks counted from 1 January, so every week belongs to one year
      APPEND VALUE #( ( |{ day }| ) ( |{ day(4) }-{ day+4(2) }-{ day+6(2) }| )
                      ( day_name( day ) ) ( month_name( month ) )
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
      ( iobjnm = 'ZCLSERV' attributes = VALUE #( ( 'ZCLSETNG' ) )
        rows = VALUE #( FOR v IN services( )
                        ( VALUE #( ( v-code ) ( COND #( WHEN v-name CS `Telehealth` THEN `Remote` ELSE `In person` ) ) ) ) ) )
      ( iobjnm = 'ZCLDATE' attributes = VALUE #( ( 'ZCLTHEDT' ) ( 'ZCLDAYNM' ) ( 'ZCLMONNM' ) ( 'ZCLYEAR' ) ( 'ZCLQTR' )
                                                 ( 'ZCLMONTH' ) ( 'ZCLWEEK' ) ( 'ZCLDAYOM' ) )
        rows = date_rows )
      ( iobjnm = 'ZCLSITE' attributes = VALUE #( ( 'ZCLCITY' ) )
        rows = VALUE #( ( VALUE #( ( `NORTH` ) ( `Northfield` ) ) ) ( VALUE #( ( `SOUTH` ) ( `Southport` ) ) ) ) )
      " R01 to R04 at both sites, R05 only in the north: a room is known only with its site. The south is loaded first
      " (BW makes the SIDs of a load in key order), so the SIDs are not in the order of the names, which the members
      " follow (OrderByColumn)
      ( iobjnm = 'ZCLROOM' compounding = VALUE #( ( 'ZCLSITE' ) ) attributes = VALUE #( ( 'ZCLRTYPE' ) )
        rows = VALUE #( ( VALUE #( ( `SOUTH` ) ( `R01` ) ( `Consultation` ) ) )
                        ( VALUE #( ( `SOUTH` ) ( `R02` ) ( `Treatment` ) ) )
                        ( VALUE #( ( `SOUTH` ) ( `R03` ) ( `Treatment` ) ) )
                        ( VALUE #( ( `SOUTH` ) ( `R04` ) ( `Consultation` ) ) ) ) )
      ( iobjnm = 'ZCLROOM' compounding = VALUE #( ( 'ZCLSITE' ) ) attributes = VALUE #( ( 'ZCLRTYPE' ) )
        rows = VALUE #( ( VALUE #( ( `NORTH` ) ( `R01` ) ( `Consultation` ) ) )
                        ( VALUE #( ( `NORTH` ) ( `R02` ) ( `Consultation` ) ) )
                        ( VALUE #( ( `NORTH` ) ( `R03` ) ( `Treatment` ) ) )
                        ( VALUE #( ( `NORTH` ) ( `R04` ) ( `Treatment` ) ) )
                        ( VALUE #( ( `NORTH` ) ( `R05` ) ( `Imaging` ) ) ) ) ) ).
  ENDMETHOD.

  METHOD texts.
    " the keys of the master data, and per value of an attribute its text
    DATA(catalog) = services( ).
    LOOP AT master_data( ) INTO DATA(md).
      DATA(keys) = lines( md-compounding ) + 1.
      LOOP AT md-rows INTO DATA(fields).
        DATA(key) = fields[ keys ].
        DATA(text) = SWITCH ty_text( md-iobjnm
          WHEN 'ZCLPAT' THEN VALUE #( long = fields[ 2 ] )
          WHEN 'ZCLDOC' THEN VALUE #( long = fields[ 2 ] )
          WHEN 'ZCLDIAG' THEN VALUE #( long = fields[ 2 ] )
          WHEN 'ZCLVTYPE' THEN VALUE #( short = key
                                        long  = COND #( WHEN key = `Telehealth` THEN `Telehealth Consultation`
                                                        ELSE |{ key } Visit| ) )
          WHEN 'ZCLSERV' THEN VALUE #( long = catalog[ code = key ]-name )
          WHEN 'ZCLDATE' THEN VALUE #( short = fields[ 2 ] long = long_date( CONV d( key ) ) )
          WHEN 'ZCLSITE' THEN VALUE #( short = |{ to_mixed( key ) } Site|
                                       long  = |{ to_mixed( key ) } Site, { fields[ 2 ] }| )
          " the room type and number: Consultation Room 1
          WHEN 'ZCLROOM' THEN VALUE #( short = |Room { CONV i( substring( val = key off = 1 ) ) }|
                                       long  = |{ fields[ 3 ] } Room { CONV i( substring( val = key off = 1 ) ) }| ) ).
        add_text( EXPORTING iobjnm      = md-iobjnm
                            compounding = md-compounding
                            keys        = VALUE #( FOR i = 1 UNTIL i > keys ( fields[ i ] ) )
                            text        = text
                  CHANGING  texts       = result ).
        LOOP AT md-attributes INTO DATA(attribute).
          DATA(value) = fields[ keys + sy-tabix ].
          add_text( EXPORTING iobjnm = attribute
                              keys   = VALUE #( ( value ) )
                              text   = attribute_text( iobjnm = attribute value = value )
                    CHANGING  texts  = result ).
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
    " the fiscal time: the variants as SAP's standard ones, and per variant the years and periods of the calendar
    DATA(variants) = VALUE string_table( ( `K1` ) ( `K2` ) ( `K4` ) ).
    LOOP AT variants INTO DATA(variant).
      DATA(special) = substring( val = variant off = 1 ).
      add_text( EXPORTING iobjnm = 'ZCLFISCVR'
                          keys   = VALUE #( ( variant ) )
                          text   = VALUE #( short = |Calendar Year ({ variant })|
                                            long  = |Calendar Year, { special } Special | &&
                                                    |Period{ COND string( WHEN special <> `1` THEN `s` ) }| )
                CHANGING  texts  = result ).
      DO c_last_day(4) - c_first_day(4) + 1 TIMES.
        DATA(year) = CONV string( c_first_day(4) + sy-index - 1 ).
        add_text( EXPORTING iobjnm      = 'ZCLFISCYR'
                            compounding = VALUE #( ( 'ZCLFISCVR' ) )
                            keys        = VALUE #( ( variant ) ( year ) )
                            text        = VALUE #( long = |Fiscal Year { year }| )
                  CHANGING  texts       = result ).
        DO 12 TIMES.
          DATA(period) = |{ sy-index WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.
          add_text( EXPORTING iobjnm      = 'ZCLFISCPR'
                              compounding = VALUE #( ( 'ZCLFISCVR' ) )
                              keys        = VALUE #( ( variant ) ( |{ year }{ period }| ) )
                              text        = VALUE #( short = |{ period }/{ year }|
                                                     long  = |Period { period }/{ year }, | &&
                                                             |{ month_name( sy-index ) } { year }| )
                    CHANGING  texts       = result ).
        ENDDO.
      ENDDO.
    ENDLOOP.
  ENDMETHOD.

  METHOD attribute_text.
    result-long = SWITCH string( iobjnm
      WHEN 'ZCLBYEAR' THEN |Born { value }|
      WHEN 'ZCLAGEGR' THEN SWITCH string( value WHEN `0-17`  THEN `Children (0-17)`
                                           WHEN `18-39` THEN `Young Adults (18-39)`
                                           WHEN `40-64` THEN `Adults (40-64)`
                                           ELSE |Seniors ({ value })| )
      " O+: O Positive
      WHEN 'ZCLBLOOD' THEN |{ substring( val = value len = strlen( value ) - 1 ) } | &&
                           |{ COND string( WHEN substring( val = value off = strlen( value ) - 1 ) = `+` THEN `Positive`
                                      ELSE `Negative` ) }|
      WHEN 'ZCLINSUR' THEN SWITCH string( value WHEN `Self-pay` THEN `Self-paying Patient`
                                           ELSE |{ value } Health Insurance| )
      WHEN 'ZCLREGIO' THEN |{ value } Region|
      WHEN 'ZCLDEPT'  THEN |Department of { value }|
      WHEN 'ZCLEXPER' THEN |{ value } Years in Practice|
      WHEN 'ZCLSETNG' THEN |{ value } Care|
      WHEN 'ZCLTHEDT' THEN long_date( CONV d( replace( val = value sub = `-` with = `` occ = 0 ) ) )
      WHEN 'ZCLYEAR'  THEN |Year { value }|
      WHEN 'ZCLQTR'   THEN |{ SWITCH string( value WHEN `Q1` THEN `1st` WHEN `Q2` THEN `2nd` WHEN `Q3` THEN `3rd`
                                              ELSE `4th` ) } Quarter|
      WHEN 'ZCLMONTH' THEN month_name( CONV i( value ) )
      WHEN 'ZCLWEEK'  THEN |Week { value }|
      WHEN 'ZCLDAYOM' THEN |Day { value }|
      WHEN 'ZCLRTYPE' THEN |{ value } Room|
      ELSE value ).
    result-short = SWITCH string( iobjnm
      WHEN 'ZCLAGEGR' OR 'ZCLBLOOD' OR 'ZCLTHEDT' OR 'ZCLINSUR' THEN value
      WHEN 'ZCLDAYNM' OR 'ZCLMONNM' THEN substring( val = value len = 3 ) ).
  ENDMETHOD.

  METHOD add_text.
    IF keys[ lines( keys ) ] IS INITIAL.
      RETURN.
    ENDIF.
    READ TABLE texts ASSIGNING FIELD-SYMBOL(<texts>) WITH KEY iobjnm = iobjnm.
    IF sy-subrc <> 0.
      APPEND VALUE #( iobjnm = iobjnm compounding = compounding ) TO texts ASSIGNING <texts>.
    ENDIF.
    INSERT concat_lines_of( table = keys sep = `/` ) INTO TABLE <texts>-seen.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(new_row) = keys.
    APPEND COND string( WHEN text-short IS NOT INITIAL THEN text-short ELSE text-long ) TO new_row.
    APPEND text-long TO new_row.
    APPEND new_row TO <texts>-rows.
  ENDMETHOD.

  METHOD month_name.
    DATA(names) = VALUE string_table( ( `January` ) ( `February` ) ( `March` ) ( `April` ) ( `May` ) ( `June` )
                                      ( `July` ) ( `August` ) ( `September` ) ( `October` ) ( `November` )
                                      ( `December` ) ).
    result = names[ month ].
  ENDMETHOD.

  METHOD day_name.
    " 1 January 1900 was a Monday
    DATA(names) = VALUE string_table( ( `Monday` ) ( `Tuesday` ) ( `Wednesday` ) ( `Thursday` ) ( `Friday` )
                                      ( `Saturday` ) ( `Sunday` ) ).
    result = names[ ( day - CONV d( '19000101' ) ) MOD 7 + 1 ].
  ENDMETHOD.

  METHOD long_date.
    result = |{ day_name( day ) }, { CONV i( day+6(2) ) } { month_name( CONV i( day+4(2) ) ) } { day(4) }|.
  ENDMETHOD.

  METHOD room.
    IF visit-physician = 0.
      RETURN.
    ENDIF.
    result-site = COND #( WHEN visit-physician MOD 2 = 0 THEN `NORTH` ELSE `SOUTH` ).
    DATA(rooms) = COND i( WHEN result-site = `NORTH` THEN 5 ELSE 4 ).
    result-room = |R0{ visit-patient MOD rooms + 1 }|.
  ENDMETHOD.

  METHOD fiscal.
    result-fiscvarnt = SWITCH #( index MOD 3 WHEN 1 THEN 'K1' WHEN 2 THEN 'K2' ELSE 'K4' ).
    result-fiscyear = visit-day(4).
    result-fiscper = |{ visit-day(4) }0{ visit-day+4(2) }|.
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
    remove_catalogs( ).
    " the providers and the views use the characteristics, so they go first; the fact views select from the providers
    LOOP AT VALUE string_table( ( CONV #( c_adso ) ) ( CONV #( c_cube ) ) ) INTO DATA(provider).
      TRY.
          IF NEW zzxxmla1_cl_bw_view_gen( )->delete_fact_view( CONV #( provider ) ) = abap_true.
            write( |delete fact views of { provider }: done| ).
          ENDIF.
        CATCH cx_dd_ddl_exception INTO DATA(error).
          write( |delete fact views of { provider }: FAILED, { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
    delete_adso( ).
    delete_cube( ).
    delete_views( ).
    delete_hierarchies( ).
    delete_hierarchy_copies( ).
    delete_infoobjects( ).
  ENDMETHOD.

  METHOD delete_hierarchy_copies.
    " the copies' not-assigned views read the SID tables (ZZXXMLA1_CL_BW_HIERARCHY_COPY)
    DATA(copy) = NEW zzxxmla1_cl_bw_hierarchy_copy( ).
    LOOP AT characteristics( ) INTO DATA(cha) WHERE hierarchies = abap_true.
      TRY.
          copy->delete_tables( cha-name ).
        CATCH zzxxmla1_cx_bw_hierarchy INTO DATA(error).
          write( |delete hierarchy copies of { cha-name }: FAILED, { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
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
    IF cl_rso_adso_api=>exist( c_adso ) <> abap_true.
      RETURN.
    ENDIF.
    TRY.
        cl_rso_adso_api=>delete( i_adsonm         = c_adso
                                 i_with_cto       = abap_false
                                 i_force_deletion = abap_true ).
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
        i_check_dependent = abap_false
        i_manual          = abap_false
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
    DATA compounds TYPE STANDARD TABLE OF bapi6108cm WITH DEFAULT KEY.
    DATA external TYPE STANDARD TABLE OF bapi6108hc WITH DEFAULT KEY.
    external = VALUE #( FOR e IN cha-hie_external ( chabasnm = cha-name iobjnm = e ) ).
    DATA(datatp) = COND datatype_d( WHEN cha-datatp IS INITIAL THEN 'CHAR' ELSE cha-datatp ).
    DATA(details) = VALUE bapi6108(
      infoobject = cha-name
      version    = c_objvers-modified
      type       = c_iobjtp-charact
      textshort  = cha-text
      textlong   = cha-text
      infoarea   = c_infoarea
      chabasnm   = cha-name
      datatp     = datatp
      intlen     = cha-leng
      leng       = cha-leng
      outputlen  = cha-leng
      lowercase  = COND #( WHEN datatp = 'CHAR' THEN abap_true )
      " language-dependent short, medium and long texts, not time dependent
      txttabfl   = '1'
      txtshfl    = abap_true
      txtmdfl    = abap_true
      txtlgfl    = abap_true
      nolangu    = abap_false
      txttimfl   = '0'
      attribfl   = COND #( WHEN cha-attributes IS NOT INITIAL THEN abap_true )
      hietabfl   = cha-hierarchies
      hieverfl   = cha-hie_versions
      hienmtfl   = cha-hie_timedep
      hieintfl   = cha-hie_intervals
      authrelfl  = cha-auth_relevant ).
    LOOP AT cha-attributes INTO DATA(attribute).
      APPEND VALUE #( chabasnm = cha-name
                      objvers  = c_objvers-modified
                      attrinm  = attribute
                      posit    = sy-tabix
                      attritp  = 'DIS'
                      f4order  = sy-tabix
                      atrtimfl = '0' ) TO attributes.
    ENDLOOP.
    LOOP AT cha-compounding INTO DATA(compounding).
      APPEND VALUE #( infoobject = cha-name
                      objvers    = c_objvers-modified
                      posit      = sy-tabix
                      iobjcmp    = compounding ) TO compounds.
    ENDLOOP.
    CALL FUNCTION 'BAPI_IOBJ_CREATE'
      EXPORTING
        details     = details
      IMPORTING
        infoobject  = iobj
        return      = return_line
      TABLES
        compounds   = compounds
        attributes  = attributes
        hierarchycharacteristics = external
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
      version    = c_objvers-modified
      type       = c_iobjtp-keyfigure
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
                      objvers   = c_objvers-modified
                      dimension = dimension
                      textlong  = dime-text
                      iobjtp    = dime-iobjtp ) TO dimension_table.
      LOOP AT dime-iobjnms INTO DATA(iobjnm).
        DATA(dimension_position) = sy-tabix.
        position = position + 1.
        APPEND VALUE #( infocube   = c_cube
                        objvers    = c_objvers-modified
                        dimension  = dimension
                        posit      = dimension_position
                        infoobject = iobjnm ) TO dimension_infoobjects.
        APPEND VALUE #( infocube   = c_cube
                        objvers    = c_objvers-modified
                        posit      = position
                        infoobject = iobjnm
                        iobjtp     = dime-iobjtp ) TO infoobjects.
      ENDLOOP.
    ENDLOOP.
    LOOP AT key_figures( ) INTO DATA(kyf).
      position = position + 1.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = c_objvers-modified
                      posit      = position
                      infoobject = kyf-name
                      iobjtp     = c_iobjtp-keyfigure ) TO infoobjects.
    ENDLOOP.
    DATA(details) = VALUE bapi6112( infocube = c_cube
                                    objvers  = c_objvers-modified
                                    textlong = 'Clinic Visits'
                                    infoarea = c_infoarea
                                    cubetype = c_cubetype_basic ).
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
    DATA(keys) = lines( md-compounding ) + 1.
    LOOP AT md-rows INTO DATA(fields).
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      LOOP AT md-compounding INTO DATA(compounding).
        ASSIGN COMPONENT |/BIC/{ compounding }| OF STRUCTURE <row> TO <value>.
        <value> = fields[ sy-tabix ].
      ENDLOOP.
      ASSIGN COMPONENT |/BIC/{ md-iobjnm }| OF STRUCTURE <row> TO <value>.
      <value> = fields[ keys ].
      ASSIGN COMPONENT 'OBJVERS' OF STRUCTURE <row> TO <value>.
      <value> = c_objvers-active.
      LOOP AT md-attributes INTO DATA(attribute).
        ASSIGN COMPONENT |/BIC/{ attribute }| OF STRUCTURE <row> TO <value>.
        <value> = fields[ sy-tabix + keys ].
      ENDLOOP.
    ENDLOOP.
    attributes = VALUE #( FOR a IN md-attributes ( iobjnm = a ) ).
    CALL FUNCTION 'RSDMD_WRITE_ATTRIBUTES_TEXTS'
      EXPORTING
        i_iobjnm               = md-iobjnm
        i_tabclass             = c_tabclass-md
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

  METHOD load_texts.
    " rows of the text table: the compounding, the key, the language and the short, medium and long text
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DATA data TYPE REF TO data.
    DATA messages TYPE rsarr_t_idocstate.
    DATA subrc TYPE sy-subrc.
    DATA described TYPE REF TO cl_abap_typedescr.
    cl_abap_typedescr=>describe_by_name( EXPORTING  p_name         = |/BIC/T{ texts-iobjnm }|
                                         RECEIVING  p_descr_ref    = described
                                         EXCEPTIONS type_not_found = 1
                                                    OTHERS         = 2 ).
    IF sy-subrc <> 0.
      write( |texts of { texts-iobjnm }: FAILED, no text table /BIC/T{ texts-iobjnm }| ).
      RETURN.
    ENDIF.
    DATA(line) = CAST cl_abap_structdescr( described ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    DATA(keys) = lines( texts-compounding ) + 1.
    LOOP AT texts-rows INTO DATA(fields).
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      LOOP AT texts-compounding INTO DATA(compounding).
        ASSIGN COMPONENT |/BIC/{ compounding }| OF STRUCTURE <row> TO <value>.
        <value> = fields[ sy-tabix ].
      ENDLOOP.
      ASSIGN COMPONENT |/BIC/{ texts-iobjnm }| OF STRUCTURE <row> TO <value>.
      <value> = fields[ keys ].
      ASSIGN COMPONENT 'LANGU' OF STRUCTURE <row> TO <value>.
      <value> = 'E'.
      ASSIGN COMPONENT 'TXTSH' OF STRUCTURE <row> TO <value>.
      <value> = fields[ keys + 1 ].
      ASSIGN COMPONENT 'TXTMD' OF STRUCTURE <row> TO <value>.
      <value> = fields[ keys + 2 ].
      ASSIGN COMPONENT 'TXTLG' OF STRUCTURE <row> TO <value>.
      <value> = fields[ keys + 2 ].
    ENDLOOP.
    CALL FUNCTION 'RSDMD_WRITE_ATTRIBUTES_TEXTS'
      EXPORTING
        i_iobjnm               = texts-iobjnm
        i_tabclass             = c_tabclass-text
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
    write( |texts of { texts-iobjnm }: { lines( <table> ) } records, | &&
           |{ COND string( WHEN ok = abap_true THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
  ENDMETHOD.

  METHOD load_hierarchy.
    DATA htab TYPE ty_t_htab.
    DATA jtab TYPE ty_t_jtab.
    DATA texts TYPE rsndi_t_hiedirt.
    DATA node_texts TYPE rsndi_t_thiernode.
    DATA messages TYPE ty_t_ndi_message.
    DATA subrc TYPE sy-subrc.
    DATA hieid TYPE rshieid.
    add_node( EXPORTING iobjnm   = hierarchy-iobjnm
                        nodes    = hierarchy-nodes
                        node     = hierarchy-nodes[ parent = `` ]
                        parentid = 0
                        tlevel   = 1
              CHANGING  htab     = htab
                        jtab     = jtab ).
    texts = VALUE #( ( langu = 'E' txtsh = hierarchy-text txtmd = hierarchy-text txtlg = hierarchy-text ) ).
    node_texts = VALUE #( FOR n IN hierarchy-nodes WHERE ( text IS NOT INITIAL )
                          ( langu = 'E' nodename = n-name txtsh = n-text txtmd = n-text txtlg = n-text ) ).
    " a link node's text is its original's
    SORT node_texts BY nodename.
    DELETE ADJACENT DUPLICATES FROM node_texts COMPARING nodename.
    DATA(header) = VALUE rsndi_s_hierupdate( hienm    = hierarchy-name
                                             version  = hierarchy-version
                                             iobjnm   = hierarchy-iobjnm
                                             norestnode = hierarchy-norest
                                             datefrom = hierarchy-datefrom
                                             dateto   = hierarchy-dateto ).
    CALL FUNCTION 'RSNDI_SHIE_STRUCTURE_UPDATE4'
      EXPORTING
        i_s_hiehead   = header
        i_t_hiedirt   = texts
        i_t_hierstruc = htab
        i_t_thiernode = node_texts
        i_t_nodenames = VALUE rsndi_t_nodenmstr( )
        i_t_hierintvl = jtab
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
    write( |hierarchy { hierarchy-name } version { hierarchy-version }, { hierarchy-datefrom DATE = ISO } to | &&
           |{ hierarchy-dateto DATE = ISO }: { lines( htab ) } nodes | &&
           |({ lines( VALUE ty_t_htab( FOR h IN htab WHERE ( link = abap_true ) ( h ) ) ) } links, | &&
           |{ lines( jtab ) } intervals), | &&
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
      DATA(index) = sy-tabix.
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT 'ZCLPAT' OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-patient <> 0 THEN |{ visit-patient }| ).
      ASSIGN COMPONENT 'ZCLDOC' OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-physician <> 0 THEN |{ visit-physician }| ).
      ASSIGN COMPONENT 'ZCLDIAG' OF STRUCTURE <row> TO <value>.
      <value> = visit-diagnosis.
      ASSIGN COMPONENT 'ZCLVTYPE' OF STRUCTURE <row> TO <value>.
      <value> = visit-visit_type.
      ASSIGN COMPONENT 'ZCLSERV' OF STRUCTURE <row> TO <value>.
      <value> = service( visit = visit index = index ).
      ASSIGN COMPONENT 'ZCLDATE' OF STRUCTURE <row> TO <value>.
      <value> = visit-day.
      DATA(room) = room( visit ).
      ASSIGN COMPONENT 'ZCLSITE' OF STRUCTURE <row> TO <value>.
      <value> = room-site.
      ASSIGN COMPONENT 'ZCLROOM' OF STRUCTURE <row> TO <value>.
      <value> = room-room.
      DATA(fiscal) = fiscal( visit = visit index = index ).
      ASSIGN COMPONENT 'ZCLFISCVR' OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscvarnt.
      ASSIGN COMPONENT 'ZCLFISCPR' OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscper.
      ASSIGN COMPONENT 'ZCLFISCYR' OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscyear.
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
        i_curr_conversion  = abap_false
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

  METHOD create_adso.
    DATA objects TYPE cl_rso_adso_api=>tn_t_object.
    DATA messages TYPE rs_t_msg.
    DATA error TYPE REF TO cx_root.
    " the characteristics of the cube with BW's calendar in place of the date; 0CALDAY has no SID table, so no view
    objects = VALUE #( FOR c IN VALUE ty_t_iobjnm( ( 'ZCLPAT' ) ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ( 'ZCLVTYPE' ) ( 'ZCLSERV' )
                                                   ( 'ZCLSITE' )
                                                   ( 'ZCLROOM' ) ( '0CALDAY' ) ( '0CALWEEK' ) ( '0CALMONTH' )
                                                   ( '0CALQUARTER' ) ( '0CALYEAR' ) ( 'ZCLFISCVR' )
                                                   ( 'ZCLFISCYR' ) ( 'ZCLFISCPR' ) )
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
                                           i_with_cto    = abap_false
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
    DATA(service_field) = iobj_field( struct = line iobjnm = 'ZCLSERV' ).
    DATA(site) = iobj_field( struct = line iobjnm = 'ZCLSITE' ).
    DATA(room_field) = iobj_field( struct = line iobjnm = 'ZCLROOM' ).
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
    DATA(fiscvarnt) = iobj_field( struct = line iobjnm = 'ZCLFISCVR' ).
    DATA(fiscper) = iobj_field( struct = line iobjnm = 'ZCLFISCPR' ).
    DATA(fiscyear) = iobj_field( struct = line iobjnm = 'ZCLFISCYR' ).
    LOOP AT visits INTO DATA(visit).
      DATA(index) = sy-tabix.
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT patient OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-patient <> 0 THEN |{ visit-patient }| ).
      ASSIGN COMPONENT physician OF STRUCTURE <row> TO <value>.
      <value> = COND string( WHEN visit-physician <> 0 THEN |{ visit-physician }| ).
      ASSIGN COMPONENT diagnosis OF STRUCTURE <row> TO <value>.
      <value> = visit-diagnosis.
      ASSIGN COMPONENT visit_type OF STRUCTURE <row> TO <value>.
      <value> = visit-visit_type.
      ASSIGN COMPONENT service_field OF STRUCTURE <row> TO <value>.
      <value> = service( visit = visit index = index ).
      DATA(room) = room( visit ).
      ASSIGN COMPONENT site OF STRUCTURE <row> TO <value>.
      <value> = room-site.
      ASSIGN COMPONENT room_field OF STRUCTURE <row> TO <value>.
      <value> = room-room.
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
      DATA(fiscal) = fiscal( visit = visit index = index ).
      ASSIGN COMPONENT fiscvarnt OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscvarnt.
      ASSIGN COMPONENT fiscper OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscper.
      ASSIGN COMPONENT fiscyear OF STRUCTURE <row> TO <value>.
      <value> = fiscal-fiscyear.
    ENDLOOP.
    CALL FUNCTION 'RSDSO_WRITE_API'
      EXPORTING
        i_adsonm            = c_adso
        i_activate_data     = abap_true
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

  METHOD deploy_schemas.
    LOOP AT providers INTO DATA(provider).
      DATA(schema) = VALUE zzxxmla1_cl_schema_def=>ty_schema( ).
      TRY.
          schema = propose( provider ).
        CATCH zzxxmla1_cx_bw_provider INTO DATA(error).
          write( |proposal of { provider }: FAILED, { error->get_text( ) }| ).
          CONTINUE.
        CATCH zzxxmla1_cx_xom INTO DATA(xom_error).
          write( |proposal of { provider }: FAILED, { xom_error->error_message }| ).
          CONTINUE.
      ENDTRY.
      tick_hierarchies( CHANGING schema = schema ).
      accept( catalog = provider schema = schema ).
      IF provider = c_cube.
        accept( catalog = c_test_catalog schema = test_schema( schema ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD test_schema.
    DATA usage TYPE zzxxmla1_cl_schema_def=>ty_dimension_usage.
    result = schema.
    result-name = c_test_catalog.
    LOOP AT result-cubes ASSIGNING FIELD-SYMBOL(<cube>).
      <cube>-name = c_test_catalog.
      <cube>-annotations = without_extensions( <cube>-annotations ).
      " copies, so the InfoCube's schema keeps its annotations
      LOOP AT <cube>-dimensions ASSIGNING FIELD-SYMBOL(<node>) WHERE name = `DimensionUsage`.
        DATA(source) = CAST zzxxmla1_cl_schema_def=>ty_dimension_usage( <node>-def ).
        usage = source->*.
        usage-annotations = without_extensions( usage-annotations ).
        <node>-def = NEW zzxxmla1_cl_schema_def=>ty_dimension_usage( usage ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD without_extensions.
    IF annotations IS NOT BOUND.
      RETURN.
    ENDIF.
    DATA(kept) = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation(
      FOR a IN annotations->array WHERE ( name <> zzxxmla1_cl_schema=>c_members_with_facts
                                          AND name <> zzxxmla1_cl_schema=>c_omit_empty_cells ) ( a ) ).
    IF kept IS NOT INITIAL.
      result = NEW #( array = kept ).
    ENDIF.
  ENDMETHOD.

  METHOD tick_hierarchies.
    LOOP AT schema-dimensions ASSIGNING FIELD-SYMBOL(<dimension>).
      DATA(characteristic) = CONV rsiobjnm( zzxxmla1_cl_bw_view_gen=>characteristic_of_view( <dimension>-table ) ).
      IF characteristic IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(bw_hierarchies) = zzxxmla1_cl_bw_hierarchy_copy=>offered( characteristic ).
      LOOP AT bw_hierarchies INTO DATA(offered) WHERE supported = abap_true.
        DATA(annotations) = NEW zzxxmla1_cl_schema_def=>ty_annotations(
          array = VALUE zzxxmla1_cl_schema_def=>ty_t_annotation( ( name = zzxxmla1_cl_schema=>c_bw_hierarchy
                                                                   cdata = offered-name ) ) ).
        IF offered-version IS NOT INITIAL.
          APPEND VALUE #( name = zzxxmla1_cl_schema=>c_bw_hierarchy_version cdata = offered-version )
            TO annotations->array.
        ENDIF.
        APPEND VALUE #( name            = offered-hierarchy
                        visible         = abap_true
                        has_all         = abap_true
                        all_member_name = |All { offered-text }|
                        caption         = offered-text
                        annotations     = annotations ) TO <dimension>-hierarchies.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD propose.
    DATA(reader) = NEW zzxxmla1_cl_bw_provider( ).
    DATA(read) = reader->read( provider ).
    DATA(defaults) = NEW zzxxmla1_cl_schema_defaults( )->propose( read ).
    IF defaults-selection IS NOT INITIAL.
      read = reader->read( name = provider selection = defaults-selection ).
    ENDIF.
    result = NEW zzxxmla1_cl_schema_proposal( )->propose( provider = read time = defaults-time )-schema.
  ENDMETHOD.

  METHOD accept.
    DATA(response) = NEW zzxxmla1_cl_schema_api( )->handle( VALUE #(
      method     = `POST`
      path       = |{ zzxxmla1_cl_schema_api=>c_path }accept|
      parameters = VALUE #( ( name = `catalog` value = catalog ) )
      body       = zzxxmla1_cl_schema_def=>to_xml( schema ) ) ).
    write( |catalog { catalog }: { COND string( WHEN response-status = 200 THEN `accepted`
                                                ELSE |FAILED, { response-status } { response-body }| ) }| ).
  ENDMETHOD.

  METHOD remove_catalogs.
    DATA(datasources) = zzxxmla1_cl_files=>read( zzxxmla1_cl_files=>c_datasources )-content.
    DATA(api) = NEW zzxxmla1_cl_schema_api( ).
    " the catalogs of both providers and the test catalog, and the ones fixing the fiscal year variant to K4 that
    " earlier runs deployed
    LOOP AT VALUE string_table( ( CONV #( c_cube ) ) ( CONV #( c_adso ) ) ( c_test_catalog ) ( |{ c_cube }_K4| )
                                ( |{ c_adso }_K4| ) )
         INTO DATA(catalog).
      IF datasources NS |<Catalog name="{ catalog }">|.
        CONTINUE.
      ENDIF.
      DATA(response) = api->handle( VALUE #( method     = `POST`
                                             path       = |{ zzxxmla1_cl_schema_api=>c_path }remove|
                                             parameters = VALUE #( ( name = `catalog` value = catalog ) ) ) ).
      write( |remove catalog { catalog }: { COND string( WHEN response-status = 200 THEN `done`
                                                         ELSE |FAILED, { response-status } { response-body }| ) }| ).
    ENDLOOP.
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
    result = COND #( WHEN without_namespace = abap_true THEN zzxxmla1_cl_bw_view_gen=>view_column( field ) ELSE field ).
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
