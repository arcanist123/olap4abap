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
"! The analysis authorization scenarios of the clinic demo (docs/clinic-demo.md, Authorization scenarios): BW analysis
"! authorizations ZCLA_* on the authorization-relevant physician ZCLDOC and diagnosis ZCLDIAG of the providers
"! ZCLVISIT and ZCLVISITA, and per scenario a test user ZZXXMLA1_ANN that has them, for comparing olap4abap's check
"! with BW's (the probe ZZXXMLA1_CL_BW_AUTH_PROBE run for the user, docs/next-steps.md, Now: analysis authorisations).
"! Every authorization carries the special characteristics BW requires (0TCAIPROV ZCLVISIT*, 0TCAACTVT 03, 0TCAVALID
"! *); hierarchy lines match by name and version (validity 1, Name and Version Identical), the matching olap4abap
"! supports. The authorizations are written with BW's API (RSEC_CREATE_AUTHORIZATION_API, activated) and assigned to
"! the users directly (RSEC_ASSIGN_USER_AUTH_API, table RSECUSERAUTH), so the users need no S_RS_AUTH. The users are
"! service users (type S: their password never has to be changed, for HTTP logons) with the profile ZZXXMLA1_REP, the
"! reporting authorizations S_RS_COMP, S_RS_COMP1 and S_RFC and nothing else. Without a password they get a generated
"! one nobody knows: they cannot log on, but BW's checks can still run for them.
"! No scenario has a variable ($ value) or a relative level (node type 4): BW accepts a variable only if it exists as
"! a customer exit variable of the characteristic (the API leaves the line out otherwise), and corrects type 4 to the
"! complete hierarchy (3) without a node variable; olap4abap does not support variables (docs/mvp-scope.md).
"! A run deletes the test users and every analysis authorization ZCLA_* and creates them again; the profile is created
"! or changed. The clinic generator deletes them with the demo (they name its characteristics and hierarchies). Run
"! with program ZZXXMLA1_SETUP (with a password) or sapcli class execute (without).
CLASS zzxxmla1_cl_bw_auth_gen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES ty_auths TYPE STANDARD TABLE OF rsauth WITH EMPTY KEY.
    "! a test user and the analysis authorizations it has
    TYPES: BEGIN OF ty_scenario,
             name        TYPE string,
             user        TYPE xubname,
             auths       TYPE ty_auths,
             description TYPE string,
           END OF ty_scenario.
    TYPES ty_scenarios TYPE STANDARD TABLE OF ty_scenario WITH EMPTY KEY.
    "! an analysis authorization: flat values and hierarchy nodes, without the special characteristics
    TYPES: BEGIN OF ty_authorization,
             name        TYPE rsauth,
             text        TYPE rstxt20,
             ranges      TYPE rsec_t_range_api,
             hierarchies TYPE rsec_t_hierarchy_api,
           END OF ty_authorization.
    TYPES ty_authorizations TYPE STANDARD TABLE OF ty_authorization WITH EMPTY KEY.

    CONSTANTS c_profile TYPE xuprofile VALUE 'ZZXXMLA1_REP'.
    CONSTANTS c_user_prefix TYPE string VALUE `ZZXXMLA1_A`.
    CONSTANTS c_auth_prefix TYPE string VALUE `ZCLA_`.
    CONSTANTS c_physician TYPE rsiobjnm VALUE 'ZCLDOC'.
    CONSTANTS c_diagnosis TYPE rsiobjnm VALUE 'ZCLDIAG'.

    "! The scenarios, each with its test user and analysis authorizations.
    CLASS-METHODS scenarios RETURNING VALUE(result) TYPE ty_scenarios.
    "! The analysis authorizations the scenarios use.
    CLASS-METHODS authorizations RETURNING VALUE(result) TYPE ty_authorizations.

    "! Deletes and creates the test users and the analysis authorizations; the log of the run.
    "! @parameter password | the test users' password; none: a generated one, nobody can log on as them
    METHODS run
      IMPORTING password      TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE string_table.
    "! Deletes the test users ZZXXMLA1_ANN and every analysis authorization ZCLA_*; the log of the run.
    METHODS delete
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_infoproviders TYPE string VALUE `ZCLVISIT*`.
    CONSTANTS c_org TYPE rshienm VALUE 'ZCLDOC_ORG'.
    CONSTANTS c_site TYPE rshienm VALUE 'ZCLDOC_SITE'.
    CONSTANTS c_icd TYPE rshienm VALUE 'ZCLDIAG_ICD'.
    CONSTANTS c_text_node TYPE rsiobjnm VALUE '0HIER_NODE'.
    CONSTANTS: BEGIN OF c_node_type,
                 node     TYPE rssauthhiertype VALUE '0',
                 subtree  TYPE rssauthhiertype VALUE '1',
                 to_level TYPE rssauthhiertype VALUE '2',
                 complete TYPE rssauthhiertype VALUE '3',
               END OF c_node_type.
    "! validity of a hierarchy line: Name and Version Identical
    CONSTANTS c_name_and_version TYPE rssbcompmode VALUE '1'.

    DATA log TYPE string_table.

    "! a value line of a characteristic (EQ, or BT with high, CP with a pattern)
    CLASS-METHODS range_line
      IMPORTING iobjnm        TYPE rsiobjnm
                option        TYPE rsz_operator DEFAULT 'EQ'
                low           TYPE csequence
                high          TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE rsec_s_auth_values_range.
    "! a hierarchy line: a node (a text node, or a value of the characteristic with iobjnm = node_iobjnm)
    CLASS-METHODS node
      IMPORTING iobjnm        TYPE rsiobjnm DEFAULT c_physician
                hierarchy     TYPE rshienm DEFAULT c_org
                version       TYPE rsversion DEFAULT '001'
                node_iobjnm   TYPE rsiobjnm DEFAULT c_text_node
                node          TYPE csequence
                type          TYPE rssauthhiertype DEFAULT c_node_type-subtree
                level         TYPE rssbtlevel DEFAULT '00'
      RETURNING VALUE(result) TYPE rsec_s_auth_values_hierarchy.
    "! the user name of the scenario number: ZZXXMLA1_A and the number in two digits
    CLASS-METHODS user IMPORTING number TYPE i RETURNING VALUE(result) TYPE xubname.
    "! the lines BW requires in every authorization: the providers, display, valid at all times
    CLASS-METHODS special_ranges RETURNING VALUE(result) TYPE rsec_t_range_api.
    "! whether a user name is one of the test users' (ZZXXMLA1_A and two digits)
    CLASS-METHODS is_test_user IMPORTING user TYPE csequence RETURNING VALUE(result) TYPE abap_bool.

    METHODS write IMPORTING text TYPE csequence.
    METHODS write_return IMPORTING return TYPE STANDARD TABLE.
    METHODS write_messages IMPORTING messages TYPE rs_t_msg.
    METHODS delete_all.
    METHODS create_profile.
    METHODS create_authorization IMPORTING authorization TYPE ty_authorization.
    METHODS create_user
      IMPORTING scenario TYPE ty_scenario
                password TYPE csequence.
    METHODS delete_user IMPORTING user TYPE xubname.
    METHODS delete_authorization IMPORTING auth TYPE rsauth.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_gen IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    LOOP AT run( ) INTO DATA(line).
      out->write( line ).
    ENDLOOP.
  ENDMETHOD.

  METHOD scenarios.
    result = VALUE #(
      ( name = `FULL` user = user( 1 ) auths = VALUE #( ( 'ZCLA_FULL' ) )
        description = `everything, as 0BI_ALL (the control)` )
      ( name = `NONE` user = user( 2 )
        description = `no analysis authorization` )
      ( name = `EQ` user = user( 3 ) auths = VALUE #( ( 'ZCLA_EQ' ) )
        description = `physicians 001, 008 and 012` )
      ( name = `EQ_AGG` user = user( 4 ) auths = VALUE #( ( 'ZCLA_EQ_AGG' ) )
        description = `physicians 001, 008 and 012, aggregated` )
      ( name = `BT` user = user( 5 ) auths = VALUE #( ( 'ZCLA_BT' ) )
        description = `physicians 001 to 005` )
      ( name = `BT_AGG` user = user( 6 ) auths = VALUE #( ( 'ZCLA_BT_AGG' ) )
        description = `physicians 001 to 005, aggregated` )
      ( name = `CP` user = user( 7 ) auths = VALUE #( ( 'ZCLA_CP' ) )
        description = `physicians 01*` )
      ( name = `CP_AGG` user = user( 8 ) auths = VALUE #( ( 'ZCLA_CP_AGG' ) )
        description = `physicians 01*, aggregated` )
      ( name = `NA` user = user( 9 ) auths = VALUE #( ( 'ZCLA_NA' ) )
        description = `the not assigned physician #` )
      ( name = `NA_AGG` user = user( 10 ) auths = VALUE #( ( 'ZCLA_NA_AGG' ) )
        description = `the not assigned physician #, aggregated` )
      ( name = `AGG` user = user( 11 ) auths = VALUE #( ( 'ZCLA_AGG' ) )
        description = `physicians aggregated only` )
      ( name = `H0` user = user( 12 ) auths = VALUE #( ( 'ZCLA_H0' ) )
        description = `ZCLDOC_ORG 001: the node GP only` )
      ( name = `H1` user = user( 13 ) auths = VALUE #( ( 'ZCLA_H1' ) )
        description = `ZCLDOC_ORG 001: the subtree of GP (008 there from 2025)` )
      ( name = `H2` user = user( 14 ) auths = VALUE #( ( 'ZCLA_H2' ) )
        description = `ZCLDOC_ORG 001: the subtree of SPECIAL to level 3` )
      ( name = `H3` user = user( 15 ) auths = VALUE #( ( 'ZCLA_H3' ) )
        description = `ZCLDOC_ORG 001: the complete hierarchy` )
      ( name = `HV2` user = user( 16 ) auths = VALUE #( ( 'ZCLA_HV2' ) )
        description = `ZCLDOC_ORG 002: the subtree of GP` )
      ( name = `HLEAF` user = user( 17 ) auths = VALUE #( ( 'ZCLA_HLEAF' ) )
        description = `ZCLDOC_ORG 001: the leaf 008` )
      ( name = `H1_AGG` user = user( 18 ) auths = VALUE #( ( 'ZCLA_H1_AGG' ) )
        description = `ZCLDOC_ORG 001: the subtree of GP, physicians aggregated` )
      ( name = `2HIE` user = user( 19 ) auths = VALUE #( ( 'ZCLA_2HIE' ) )
        description = `ZCLDOC_ORG 001 CARD and ZCLDOC_SITE 001 RIVER` )
      ( name = `COMB` user = user( 20 ) auths = VALUE #( ( 'ZCLA_COMB' ) )
        description = `ZCLDOC_ORG 001 PULM with ZCLDIAG_ICD RESPIRATORY` )
      ( name = `CROSS` user = user( 21 ) auths = VALUE #( ( 'ZCLA_X1' ) ( 'ZCLA_X2' ) )
        description = `009 with I10, and 012 with J45` ) ).
  ENDMETHOD.

  METHOD authorizations.
    DATA(all_diagnoses) = range_line( iobjnm = c_diagnosis option = 'CP' low = `*` ).
    DATA(aggregated) = range_line( iobjnm = c_physician low = `:` ).
    DATA(three) = VALUE rsec_t_range_api( ( range_line( iobjnm = c_physician low = `001` ) )
                                          ( range_line( iobjnm = c_physician low = `008` ) )
                                          ( range_line( iobjnm = c_physician low = `012` ) )
                                          ( all_diagnoses ) ).
    DATA(range) = VALUE rsec_t_range_api(
      ( range_line( iobjnm = c_physician option = 'BT' low = `001` high = `005` ) ) ( all_diagnoses ) ).
    DATA(pattern) = VALUE rsec_t_range_api( ( range_line( iobjnm = c_physician option = 'CP' low = `01*` ) )
                                            ( all_diagnoses ) ).
    DATA(not_assigned) = VALUE rsec_t_range_api( ( range_line( iobjnm = c_physician low = `#` ) ) ( all_diagnoses ) ).
    DATA(gp) = node( node = `GP` ).

    result = VALUE #(
      ( name = 'ZCLA_FULL' text = 'All physicians'
        ranges = VALUE #( ( range_line( iobjnm = c_physician option = 'CP' low = `*` ) ) ( all_diagnoses ) ) )
      ( name = 'ZCLA_EQ' text = '001, 008, 012' ranges = three )
      ( name = 'ZCLA_EQ_AGG' text = '001, 008, 012, :' ranges = VALUE #( BASE three ( aggregated ) ) )
      ( name = 'ZCLA_BT' text = '001 to 005' ranges = range )
      ( name = 'ZCLA_BT_AGG' text = '001 to 005, :' ranges = VALUE #( BASE range ( aggregated ) ) )
      ( name = 'ZCLA_CP' text = '01*' ranges = pattern )
      ( name = 'ZCLA_CP_AGG' text = '01*, :' ranges = VALUE #( BASE pattern ( aggregated ) ) )
      ( name = 'ZCLA_NA' text = 'Not assigned' ranges = not_assigned )
      ( name = 'ZCLA_NA_AGG' text = 'Not assigned, :' ranges = VALUE #( BASE not_assigned ( aggregated ) ) )
      ( name = 'ZCLA_AGG' text = 'Aggregated only' ranges = VALUE #( ( aggregated ) ( all_diagnoses ) ) )
      ( name = 'ZCLA_H0' text = 'ORG 001 GP node'
        ranges = VALUE #( ( all_diagnoses ) )
        hierarchies = VALUE #( ( node( node = `GP` type = c_node_type-node ) ) ) )
      ( name = 'ZCLA_H1' text = 'ORG 001 GP subtree'
        ranges = VALUE #( ( all_diagnoses ) ) hierarchies = VALUE #( ( gp ) ) )
      ( name = 'ZCLA_H2' text = 'ORG 001 SPECIAL to 3'
        ranges = VALUE #( ( all_diagnoses ) )
        hierarchies = VALUE #( ( node( node = `SPECIAL` type = c_node_type-to_level level = '03' ) ) ) )
      ( name = 'ZCLA_H3' text = 'ORG 001 complete'
        ranges = VALUE #( ( all_diagnoses ) )
        hierarchies = VALUE #( ( node( node = `CLINIC` type = c_node_type-complete ) ) ) )
      ( name = 'ZCLA_HV2' text = 'ORG 002 GP subtree'
        ranges = VALUE #( ( all_diagnoses ) ) hierarchies = VALUE #( ( node( version = '002' node = `GP` ) ) ) )
      ( name = 'ZCLA_HLEAF' text = 'ORG 001 leaf 008'
        ranges = VALUE #( ( all_diagnoses ) )
        hierarchies = VALUE #( ( node( node_iobjnm = c_physician node = `008` type = c_node_type-node ) ) ) )
      ( name = 'ZCLA_H1_AGG' text = 'ORG 001 GP, :'
        ranges = VALUE #( ( aggregated ) ( all_diagnoses ) ) hierarchies = VALUE #( ( gp ) ) )
      ( name = 'ZCLA_2HIE' text = 'ORG CARD, SITE RIVER'
        ranges = VALUE #( ( all_diagnoses ) )
        hierarchies = VALUE #( ( node( node = `CARD` ) ) ( node( hierarchy = c_site node = `RIVER` ) ) ) )
      ( name = 'ZCLA_COMB' text = 'PULM, RESPIRATORY'
        hierarchies = VALUE #( ( node( node = `PULM` ) )
                               ( node( iobjnm = c_diagnosis hierarchy = c_icd version = '' node = `RESPIRATORY` ) ) ) )
      ( name = 'ZCLA_X1' text = '009 with I10'
        ranges = VALUE #( ( range_line( iobjnm = c_physician low = `009` ) )
                          ( range_line( iobjnm = c_diagnosis low = `I10` ) ) ) )
      ( name = 'ZCLA_X2' text = '012 with J45'
        ranges = VALUE #( ( range_line( iobjnm = c_physician low = `012` ) )
                          ( range_line( iobjnm = c_diagnosis low = `J45` ) ) ) ) ).
  ENDMETHOD.

  METHOD range_line.
    result = VALUE #( iobjnm = iobjnm sign = 'I' opt = option low = low high = high ).
  ENDMETHOD.

  METHOD node.
    result = VALUE #( iobjnm   = iobjnm
                      hienm    = hierarchy
                      version  = version
                      dateto   = '99991231'
                      niobjnm  = node_iobjnm
                      node     = node
                      authtype = type
                      compmode = c_name_and_version
                      tlevel   = level ).
  ENDMETHOD.

  METHOD user.
    result = |{ c_user_prefix }{ number WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD special_ranges.
    result = VALUE #( ( range_line( iobjnm = '0TCAIPROV' option = 'CP' low = c_infoproviders ) )
                      ( range_line( iobjnm = '0TCAACTVT' low = `03` ) )
                      ( range_line( iobjnm = '0TCAVALID' option = 'CP' low = `*` ) ) ).
  ENDMETHOD.

  METHOD is_test_user.
    DATA(prefix) = strlen( c_user_prefix ).
    result = xsdbool( strlen( user ) = prefix + 2
                      AND substring( val = user len = prefix ) = c_user_prefix
                      AND substring( val = user off = prefix ) CO '0123456789' ).
  ENDMETHOD.

  METHOD run.
    CLEAR log.
    delete_all( ).
    create_profile( ).
    LOOP AT authorizations( ) INTO DATA(authorization).
      create_authorization( authorization ).
    ENDLOOP.
    LOOP AT scenarios( ) INTO DATA(scenario).
      create_user( scenario = scenario password = password ).
    ENDLOOP.
    IF password IS INITIAL.
      write( `the test users have a generated password: they cannot log on` ).
    ENDIF.
    result = log.
  ENDMETHOD.

  METHOD delete.
    CLEAR log.
    delete_all( ).
    result = log.
  ENDMETHOD.

  METHOD delete_all.
    DATA(pattern) = |{ c_user_prefix }%|.
    SELECT bname FROM usr02 WHERE bname LIKE @pattern ORDER BY bname ASCENDING INTO TABLE @DATA(users).
    LOOP AT users INTO DATA(user).
      IF is_test_user( user-bname ) = abap_true.
        delete_user( user-bname ).
      ENDIF.
    ENDLOOP.
    pattern = |{ c_auth_prefix }%|.
    SELECT DISTINCT auth FROM rsecbiau WHERE auth LIKE @pattern ORDER BY auth ASCENDING INTO TABLE @DATA(auths).
    LOOP AT auths INTO DATA(auth).
      delete_authorization( auth-auth ).
    ENDLOOP.
  ENDMETHOD.

  METHOD create_profile.
    DATA values TYPE STANDARD TABLE OF usval.
    DATA auths TYPE STANDARD TABLE OF usaut.
    DATA return TYPE bapirettab.
    DATA pstate TYPE xuaktpas.
    " display and execute of every query component, RFC calls of the reporting function groups
    DATA(fields) = VALUE string_table( ( `S_RS_COMP RSINFOAREA *` ) ( `S_RS_COMP RSINFOCUBE *` )
                                       ( `S_RS_COMP RSZCOMPTP *` ) ( `S_RS_COMP RSZCOMPID *` )
                                       ( `S_RS_COMP ACTVT 03` ) ( `S_RS_COMP ACTVT 16` )
                                       ( `S_RS_COMP1 RSZCOMPID *` ) ( `S_RS_COMP1 RSZCOMPTP *` )
                                       ( `S_RS_COMP1 RSZOWNER *` ) ( `S_RS_COMP1 ACTVT 03` ) ( `S_RS_COMP1 ACTVT 16` )
                                       ( `S_RFC RFC_TYPE FUGR` ) ( `S_RFC RFC_NAME *` ) ( `S_RFC ACTVT 16` ) ).
    SELECT SINGLE profn FROM usr10 WHERE profn = @c_profile INTO @DATA(found).
    DATA(action) = COND activ_auth( WHEN sy-subrc = 0 THEN '02' ELSE '01' ).
    LOOP AT fields INTO DATA(field).
      SPLIT field AT ` ` INTO DATA(object) DATA(name) DATA(low).
      DATA(auth) = SWITCH xuauth( object WHEN 'S_RS_COMP' THEN 'ZZXXMLA1_R01'
                                         WHEN 'S_RS_COMP1' THEN 'ZZXXMLA1_R02'
                                         ELSE 'ZZXXMLA1_R03' ).
      APPEND VALUE #( objct = object auth = auth sfield = name von = low ) TO values.
      IF NOT line_exists( auths[ auth = auth ] ).
        APPEND VALUE #( action = action objct = object auth = auth atext = 'olap4abap test users' ) TO auths.
      ENDIF.
    ENDLOOP.
    CALL FUNCTION 'SUSR_INTERFACE_PROF'
      EXPORTING
        profile                    = c_profile
        ptext                      = 'olap4abap: BW reporting of the test users'
        ptype                      = 'S'
        action                     = action
        dialog                     = ' '
      IMPORTING
        pstate                     = pstate
        return                     = return
      TABLES
        values                     = values
        auths                      = auths
      EXCEPTIONS
        not_authorized_for_auth    = 1
        params_incomplete          = 2
        not_authorized_for_profile = 3
        profile_exists             = 4
        auth_exists                = 5
        colective_profile          = 6
        bad_profile_name           = 7
        bad_auth_name              = 8
        profile_dont_exist         = 9
        authorization_overflow     = 10
        shorttext_missing          = 11
        OTHERS                     = 12.
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      write( |{ COND string( WHEN found IS INITIAL THEN `create` ELSE `change` ) } profile { c_profile }: done| ).
    ELSE.
      ROLLBACK WORK.
      write( |create profile { c_profile }: FAILED, subrc { sy-subrc }| ).
    ENDIF.
    write_return( return ).
  ENDMETHOD.

  METHOD create_authorization.
    DATA messages TYPE rs_t_msg.
    DATA(ranges) = special_ranges( ).
    APPEND LINES OF authorization-ranges TO ranges.
    CALL FUNCTION 'RSEC_CREATE_AUTHORIZATION_API'
      EXPORTING
        i_authname              = authorization-name
        i_t_range               = ranges
        i_t_hierarchy           = authorization-hierarchies
        i_short_text            = authorization-text
      IMPORTING
        e_t_messages            = messages
      EXCEPTIONS
        auth_exists             = 1
        no_authorization        = 2
        forbidden_signs_in_name = 3
        wrong_name              = 4
        authorization_is_empty  = 5
        empty_short_text        = 6
        no_change_auth          = 7
        no_create_auth          = 8
        auth_locked             = 9
        OTHERS                  = 10.
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      write( |create authorization { authorization-name }: done| ).
      " the API leaves out a line it does not accept (a variable that does not exist) with a message only
      DELETE messages WHERE msgty = 'S'.
    ELSE.
      ROLLBACK WORK.
      write( |create authorization { authorization-name }: FAILED, subrc { sy-subrc }| ).
    ENDIF.
    write_messages( messages ).
  ENDMETHOD.

  METHOD create_user.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA profiles TYPE STANDARD TABLE OF bapiprof.
    DATA generated TYPE bapipwd.
    DATA messages TYPE rs_t_msg.
    DATA generate TYPE bapiflag-bapiflag.
    generate = xsdbool( password IS INITIAL ).
    CALL FUNCTION 'BAPI_USER_CREATE1'
      EXPORTING
        username           = scenario-user
        logondata          = VALUE bapilogond( ustyp = 'S' )
        password           = VALUE bapipwd( bapipwd = password )
        address            = VALUE bapiaddr3( firstname = 'olap4abap' lastname = |Test { scenario-name }| )
        generate_pwd       = generate
      IMPORTING
        generated_password = generated
      TABLES
        return             = return.
    IF line_exists( return[ type = 'E' ] ) OR line_exists( return[ type = 'A' ] ).
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      write( |create user { scenario-user } ({ scenario-name }): FAILED| ).
      write_return( return ).
      RETURN.
    ENDIF.
    CLEAR generated.
    CLEAR return.
    profiles = VALUE #( ( bapiprof = c_profile ) ).
    CALL FUNCTION 'BAPI_USER_PROFILES_ASSIGN'
      EXPORTING
        username = scenario-user
      TABLES
        profiles = profiles
        return   = return.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = abap_true.
    IF line_exists( return[ type = 'E' ] ) OR line_exists( return[ type = 'A' ] ).
      write( |assign profile { c_profile } to { scenario-user }: FAILED| ).
      write_return( return ).
    ENDIF.
    IF scenario-auths IS NOT INITIAL.
      CALL FUNCTION 'RSEC_ASSIGN_USER_AUTH_API'
        EXPORTING
          i_username       = scenario-user
          i_t_auths        = VALUE rsec_t_auths( FOR a IN scenario-auths ( authname = a ) )
        IMPORTING
          e_t_messages     = messages
        EXCEPTIONS
          user_not_exists  = 1
          user_locked      = 2
          no_authorization = 3
          OTHERS           = 4.
      IF sy-subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
        write( |assign authorizations to { scenario-user }: FAILED, subrc { sy-subrc }| ).
        write_messages( messages ).
        RETURN.
      ENDIF.
    ENDIF.
    DATA(auths) = REDUCE string( INIT s = `` FOR a IN scenario-auths NEXT s = |{ s } { a }| ).
    write( |create user { scenario-user } { scenario-name }:{ COND string( WHEN auths IS INITIAL THEN ` -`
                                                                         ELSE auths ) }| ).
  ENDMETHOD.

  METHOD delete_user.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA messages TYPE rs_t_msg.
    SELECT auth FROM rsecuserauth WHERE uname = @user INTO TABLE @DATA(assigned).
    IF assigned IS NOT INITIAL.
      CALL FUNCTION 'RSEC_UNASSIGN_USER_AUTH_API'
        EXPORTING
          i_username       = user
          i_t_auths        = VALUE rsec_t_auths( FOR a IN assigned ( authname = a-auth ) )
        IMPORTING
          e_t_messages     = messages
        EXCEPTIONS
          user_not_exists  = 1
          user_locked      = 2
          no_authorization = 3
          OTHERS           = 4.
      IF sy-subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
        write( |unassign authorizations of { user }: FAILED, subrc { sy-subrc }| ).
        write_messages( messages ).
      ENDIF.
    ENDIF.
    CALL FUNCTION 'BAPI_USER_DELETE'
      EXPORTING
        username = user
      TABLES
        return   = return.
    IF line_exists( return[ type = 'E' ] ) OR line_exists( return[ type = 'A' ] ).
      CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
      write( |delete user { user }: FAILED| ).
      write_return( return ).
    ELSE.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = abap_true.
      write( |delete user { user }: done| ).
    ENDIF.
  ENDMETHOD.

  METHOD delete_authorization.
    CALL FUNCTION 'RSEC_DELETE_AUTHORIZATION_API'
      EXPORTING
        i_authname       = auth
      EXCEPTIONS
        auth_not_exists  = 1
        no_authorization = 2
        auth_locked      = 3
        OTHERS           = 4.
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      write( |delete authorization { auth }: done| ).
    ELSE.
      ROLLBACK WORK.
      write( |delete authorization { auth }: FAILED, subrc { sy-subrc }| ).
    ENDIF.
  ENDMETHOD.

  METHOD write.
    APPEND text TO log.
  ENDMETHOD.

  METHOD write_return.
    DATA line TYPE bapiret2.
    LOOP AT return INTO line.
      IF line-message IS NOT INITIAL.
        write( |  [{ line-type }] { line-message }| ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD write_messages.
    LOOP AT messages INTO DATA(message).
      MESSAGE ID message-msgid TYPE 'S' NUMBER message-msgno
        WITH message-msgv1 message-msgv2 message-msgv3 message-msgv4 INTO DATA(text).
      write( |  [{ message-msgty }] { text }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
