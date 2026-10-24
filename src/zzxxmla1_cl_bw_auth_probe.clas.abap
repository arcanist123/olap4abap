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
"! Probes BW's analysis authorizations on authorization-relevant characteristics with hierarchies (program
"! ZZXXMLA1_BW_AUTH_PROBE, or sapcli class execute): runs a set of queries through BW's own MDX engine
"! (BAPI_MDDATASET_*) as the current user, or as another one, and records per query whether BW answers, what, or which
"! message it gives. As another user it runs as BW's "Execute as Other User" (RSUDO) does: the analysis authorizations
"! are checked for the user that RSEC_SET_USERNAME sets (RSEC_GET_USERNAME reads it back), sy-uname stays the caller;
"! scripts/auth_probe.py checks that the answers equal a logon of the user (BW's XMLA service).
"! Made for the clinic demo's aDSO $ZCLVISITA (docs/clinic-demo.md) with its physician ZCLDOC (hierarchies version
"! dependent and entirely time dependent) and its diagnosis ZCLDIAG (a plain hierarchy).
"!
"! BW's MDX shows per hierarchy name and version the slice valid at the key date (RRT_SET_KEY_DATE; today if none is
"! set): the probe runs everything once per key date, so the slices of 2024 and of 2025 are both asked. Per key date:
"! - the total of the provider, which aggregates every characteristic;
"! - per characteristic, flat: its members and each value as slicer;
"! - per hierarchy of a characteristic (name and version): all its members;
"! - per node of the slice (text nodes and leaves, from the hierarchy table): the node as slicer, on the rows, its
"!   children and its parent;
"! - combined, per pair of characteristics: each row set of the one (its members, the members of each of its
"!   hierarchies) with each value and each text node of the other as slicer (leaves too on request);
"! - NON EMPTY: the members of each row set, and per text node its children;
"! - crossjoin: each row set of the first characteristic crossed with each of the second, one side flat, with and
"!   without NON EMPTY;
"! - levels: the members of each level of each row set (BAPI_MDPROVIDER_GET_LEVELS);
"! - pairs: a value of the first characteristic and one of the second together as slicer, for the pairs given.
"! BW's MDX has no DRILLTHROUGH (BRAINOLAPAPI 153, Statement Not Supported), so the probe asks none.
"! A query that does not name a characteristic aggregates it, which needs the aggregation authorization (:) on it.
"! The analysis authorizations that restrict the characteristics are listed by authorizations( ).
CLASS zzxxmla1_cl_bw_auth_probe DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    TYPES ty_dates TYPE STANDARD TABLE OF d WITH EMPTY KEY.
    TYPES ty_characteristics TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
    TYPES ty_hienm_range TYPE RANGE OF rshienm.
    TYPES ty_version_range TYPE RANGE OF rsversion.
    " the kinds of query
    TYPES: BEGIN OF ty_tests,
             flat           TYPE abap_bool,
             members        TYPE abap_bool,
             slicer         TYPE abap_bool,
             rows           TYPE abap_bool,
             children       TYPE abap_bool,
             parent         TYPE abap_bool,
             combined       TYPE abap_bool,
             combine_leaves TYPE abap_bool,
             non_empty      TYPE abap_bool,
             crossjoin      TYPE abap_bool,
             levels         TYPE abap_bool,
             pairs          TYPE abap_bool,
           END OF ty_tests.
    " a value of the first characteristic and one of the second
    TYPES: BEGIN OF ty_pair,
             first  TYPE string,
             second TYPE string,
           END OF ty_pair.
    TYPES ty_pairs TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY.
    " a cell of BW's answer: the members of its row (unique names and captions, one per hierarchy of the row's
    " tuple; none without rows), its value (BW's float as text, empty for an empty cell) and its status
    TYPES: BEGIN OF ty_cell,
             members  TYPE string_table,
             captions TYPE string_table,
             value    TYPE string,
             status   TYPE string,
           END OF ty_cell.
    TYPES ty_cells TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY.
    " a query and BW's answer; filter_* is the restriction on the other characteristic of a combined query; the
    " answer as text, one 'captions = formatted value' per row, its cells in ty_result
    TYPES: BEGIN OF ty_result_line,
             key_date         TYPE d,
             characteristic   TYPE rsiobjnm,
             hierarchy        TYPE c LENGTH 40,
             valid_to         TYPE d,
             test             TYPE c LENGTH 12,
             node             TYPE c LENGTH 32,
             node_type        TYPE c LENGTH 10,
             level            TYPE i,
             filter_char      TYPE rsiobjnm,
             filter_hierarchy TYPE c LENGTH 40,
             filter_node      TYPE c LENGTH 32,
             status           TYPE c LENGTH 8,
             rows             TYPE i,
             answer           TYPE string,
             message          TYPE string,
             mdx              TYPE string,
           END OF ty_result_line.
    TYPES ty_result_lines TYPE STANDARD TABLE OF ty_result_line WITH EMPTY KEY.
    TYPES BEGIN OF ty_result.
    INCLUDE TYPE ty_result_line.
    TYPES   cells TYPE ty_cells.
    TYPES END OF ty_result.
    TYPES ty_results TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.
    " a line of an analysis authorization that restricts one of the characteristics, and whether the user has it
    TYPES: BEGIN OF ty_authorization,
             auth     TYPE rsauth,
             assigned TYPE abap_bool,
             kind     TYPE c LENGTH 10,
             details  TYPE string,
           END OF ty_authorization.
    TYPES ty_authorizations TYPE STANDARD TABLE OF ty_authorization WITH EMPTY KEY.

    CONSTANTS: BEGIN OF c_status,
                 ok      TYPE c LENGTH 8 VALUE 'OK',
                 empty   TYPE c LENGTH 8 VALUE 'EMPTY',
                 no_auth TYPE c LENGTH 8 VALUE 'NO AUTH',
                 unknown TYPE c LENGTH 8 VALUE 'UNKNOWN',
                 error   TYPE c LENGTH 8 VALUE 'ERROR',
               END OF c_status.

    "! @parameter characteristics | the authorization-relevant characteristics; ZCLDOC and ZCLDIAG if none
    "! @parameter user | the user whose analysis authorizations BW checks; the current one if none
    METHODS constructor
      IMPORTING cube            TYPE string DEFAULT `$ZCLVISITA`
                characteristics TYPE ty_characteristics OPTIONAL
                measure         TYPE string DEFAULT `ZCLVISNO`
                !user           TYPE xubname DEFAULT sy-uname.

    "! Runs the queries once per key date, as the user (RSEC_SET_USERNAME for another than the current one); the key
    "! date and the user are reset afterwards. A user BW does not take is one ERROR row.
    "! @parameter pairs | the value pairs of the test pairs
    METHODS run
      IMPORTING key_dates     TYPE ty_dates
                hierarchies   TYPE ty_hienm_range OPTIONAL
                versions      TYPE ty_version_range OPTIONAL
                tests         TYPE ty_tests
                pairs         TYPE ty_pairs OPTIONAL
      RETURNING VALUE(result) TYPE ty_results.

    "! The analysis authorizations that restrict one of the characteristics (value and hierarchy authorizations,
    "! RSECVAL_STRING and RSECHIE_STRING) with all their lines, and 0BI_ALL, each with whether the current user has it
    "! (S_RS_AUTH or RSECADMIN's direct assignment), for the user of the probe.
    METHODS authorizations
      RETURNING VALUE(result) TYPE ty_authorizations.

    "! The MDX unique name of a node of a hierarchy: a text node is its name padded to 32 characters and 0HIER_NODE,
    "! a leaf (a value of the characteristic) its key.
    CLASS-METHODS node_name
      IMPORTING hierarchy      TYPE string
                characteristic TYPE csequence
                iobjnm         TYPE csequence
                nodename       TYPE csequence
      RETURNING VALUE(result)  TYPE string.

    "! An MDX statement as lines of BAPI6111MDX: every 75 characters, as BW joins the lines of 75 characters
    "! respecting blanks; the unique names have blanks inside.
    CLASS-METHODS command_lines
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_node,
             nodeid   TYPE rshienodid,
             iobjnm   TYPE rsiobjnm,
             nodename TYPE rsshnodename,
             tlevel   TYPE rstlevel,
             parentid TYPE rsparent,
           END OF ty_node.
    TYPES ty_nodes TYPE STANDARD TABLE OF ty_node WITH EMPTY KEY.
    " a level of a hierarchy as BW's MDX names it
    TYPES: BEGIN OF ty_level,
             name   TYPE string,
             unique TYPE string,
             number TYPE i,
           END OF ty_level.
    TYPES ty_levels TYPE STANDARD TABLE OF ty_level WITH EMPTY KEY.
    " a hierarchy as BW's MDX shows it at the key date, with the nodes of its slice
    TYPES: BEGIN OF ty_hierarchy,
             hienm   TYPE rshienm,
             version TYPE rsversion,
             dateto  TYPE d,
             hieid   TYPE rshieid,
             unique  TYPE string,
             label   TYPE string,
             nodes   TYPE ty_nodes,
             levels  TYPE ty_levels,
           END OF ty_hierarchy.
    TYPES ty_hierarchies TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    " a characteristic at the key date: its values and the hierarchies BW's MDX shows
    TYPES: BEGIN OF ty_characteristic,
             name        TYPE rsiobjnm,
             values      TYPE string_table,
             levels      TYPE ty_levels,
             hierarchies TYPE ty_hierarchies,
           END OF ty_characteristic.
    TYPES ty_characteristic_list TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.
    " a restriction on a characteristic for a combined query
    TYPES: BEGIN OF ty_filter,
             hierarchy TYPE string,
             node      TYPE string,
             member    TYPE string,
           END OF ty_filter.
    TYPES ty_filters TYPE STANDARD TABLE OF ty_filter WITH EMPTY KEY.
    " BW's answer to one statement
    TYPES: BEGIN OF ty_answer,
             status  TYPE c LENGTH 8,
             rows    TYPE i,
             answer  TYPE string,
             message TYPE string,
             cells   TYPE ty_cells,
           END OF ty_answer.

    CONSTANTS c_max_answer TYPE i VALUE 100000.

    DATA cube TYPE string.
    DATA user TYPE xubname.
    DATA characteristics TYPE ty_characteristics.
    DATA measure TYPE string.

    "! sets the user whose analysis authorizations BW checks (RSEC_SET_USERNAME; nothing to set for the current
    "! user if the probe's user is the current one); the user BW then checks (RSEC_GET_USERNAME)
    METHODS analysis_user
      IMPORTING !name         TYPE xubname
      RETURNING VALUE(result) TYPE xubname.
    METHODS probe_key_date
      IMPORTING key_date      TYPE d
                hierarchies   TYPE ty_hienm_range
                versions      TYPE ty_version_range
                tests         TYPE ty_tests
                pairs         TYPE ty_pairs
      RETURNING VALUE(result) TYPE ty_results.
    METHODS probe_flat
      IMPORTING key_date       TYPE d
                characteristic TYPE ty_characteristic
                tests          TYPE ty_tests
      RETURNING VALUE(result)  TYPE ty_results.
    "! the members of each level of a row set
    METHODS probe_levels
      IMPORTING !row          TYPE ty_result
                levels        TYPE ty_levels
      RETURNING VALUE(result) TYPE ty_results.
    "! each row set of the one characteristic crossed with each of the other (not two hierarchies: one side is flat), with
    "! and without NON EMPTY
    METHODS probe_crossjoin
      IMPORTING key_date      TYPE d
                rows_of       TYPE ty_characteristic
                cross_with    TYPE ty_characteristic
      RETURNING VALUE(result) TYPE ty_results.
    METHODS probe_hierarchy
      IMPORTING key_date       TYPE d
                characteristic TYPE rsiobjnm
                hierarchy      TYPE ty_hierarchy
                tests          TYPE ty_tests
      RETURNING VALUE(result)  TYPE ty_results.
    "! each row set of the one characteristic with each restriction on the other as slicer
    METHODS probe_combined
      IMPORTING key_date      TYPE d
                rows_of       TYPE ty_characteristic
                filter_of     TYPE ty_characteristic
                leaves        TYPE abap_bool
      RETURNING VALUE(result) TYPE ty_results.
    "! the values of a characteristic and its hierarchies BW's MDX shows at the current key date
    METHODS read_characteristic
      IMPORTING name          TYPE rsiobjnm
                hierarchies   TYPE ty_hienm_range
                versions      TYPE ty_version_range
      RETURNING VALUE(result) TYPE ty_characteristic.
    "! the values of a characteristic from its SID table, without the initial value
    METHODS values
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE string_table.
    METHODS mdx_hierarchies
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_hierarchies.
    "! the levels of a hierarchy BW's MDX shows (of the flat one: its unique name is the characteristic's)
    METHODS mdx_levels
      IMPORTING characteristic TYPE rsiobjnm
                hierarchy      TYPE string
      RETURNING VALUE(result)  TYPE ty_levels.
    "! the nodes of a hierarchy slice, in the order of the hierarchy table
    METHODS nodes
      IMPORTING characteristic TYPE rsiobjnm
                hieid          TYPE rshieid
      RETURNING VALUE(result)  TYPE ty_nodes.
    METHODS select
      IMPORTING rows          TYPE string
                slicer        TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE string.
    "! one query: BW's answer as text, one 'caption = value' per row
    METHODS execute
      IMPORTING mdx           TYPE string
      RETURNING VALUE(result) TYPE ty_answer.
    "! BW's answer from its axis 1 (the rows, if the statement has them) and its cells; the statement has one
    "! measure on axis 0, so a cell's ordinal is its row's
    METHODS answer_text
      IMPORTING datasetid TYPE bapi6111gen-obj_handle
                has_rows  TYPE abap_bool
      CHANGING  answer    TYPE ty_answer.
    METHODS failed
      IMPORTING return        TYPE bapiret2
                step          TYPE string
      RETURNING VALUE(result) TYPE ty_answer.
    "! runs the query of a result row and fills in BW's answer
    METHODS answered
      IMPORTING row           TYPE ty_result
      RETURNING VALUE(result) TYPE ty_result.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_probe IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    LOOP AT authorizations( ) INTO DATA(authorization).
      out->write( |{ authorization-auth } { COND string( WHEN authorization-assigned = abap_true
                                                          THEN `assigned` ELSE `not assigned` ) } {
                  authorization-kind } { authorization-details }| ).
    ENDLOOP.
    LOOP AT run( key_dates = VALUE #( ( CONV d( '20240615' ) ) ( CONV d( '20250615' ) ) ( CONV d( '99991231' ) ) )
                 tests     = VALUE #( flat = abap_true members = abap_true slicer = abap_true rows = abap_true
                                      children = abap_true parent = abap_true combined = abap_true
                                      non_empty = abap_true crossjoin = abap_true levels = abap_true ) )
         INTO DATA(row).
      out->write( |{ row-key_date } { row-characteristic } { row-hierarchy } { row-test } { row-node } {
                  row-filter_hierarchy } { row-filter_node } { row-status } { row-rows } { row-answer } {
                  row-message }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD constructor.
    me->cube = cube.
    me->characteristics = characteristics.
    IF me->characteristics IS INITIAL.
      me->characteristics = VALUE #( ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ).
    ENDIF.
    me->measure = measure.
    me->user = user.
  ENDMETHOD.

  METHOD run.
    DATA(analysis_user) = analysis_user( user ).
    analysis_user( sy-uname ).
    IF analysis_user = user.
      LOOP AT key_dates INTO DATA(key_date).
        APPEND LINES OF probe_key_date( key_date    = key_date
                                        hierarchies = hierarchies
                                        versions    = versions
                                        tests       = tests
                                        pairs       = pairs ) TO result.
      ENDLOOP.
    ELSE.
      APPEND VALUE #( test = 'USER' status = c_status-error
                      message = |BW checks the authorizations of { analysis_user }, not of { user }| ) TO result.
    ENDIF.
    CALL FUNCTION 'RRT_SET_KEY_DATE'
      EXPORTING
        i_key_date = space
        i_explicit = abap_true
      EXCEPTIONS
        x_message  = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      " the key date stays set for this session only
      CLEAR sy-subrc.
    ENDIF.
  ENDMETHOD.

  METHOD probe_key_date.
    CALL FUNCTION 'RRT_SET_KEY_DATE'
      EXPORTING
        i_key_date = key_date
        i_explicit = abap_true
      EXCEPTIONS
        x_message  = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      APPEND VALUE #( key_date = key_date test = 'KEY DATE' status = c_status-error
                      message = |RRT_SET_KEY_DATE failed ({ sy-subrc })| ) TO result.
      RETURN.
    ENDIF.

    " the hierarchies as the caller sees them: BW's metadata lists fewer to a restricted user (a row HIERARCHIES of
    " each characteristic says which), the queries ask all of them
    DATA list TYPE ty_characteristic_list.
    LOOP AT characteristics INTO DATA(name).
      APPEND read_characteristic( name        = name
                                  hierarchies = hierarchies
                                  versions    = versions ) TO list.
    ENDLOOP.
    analysis_user( user ).
    IF tests-members = abap_true.
      LOOP AT list INTO DATA(listed).
        DATA(shown) = VALUE string_table( FOR h IN mdx_hierarchies( listed-name )
                                          WHERE ( hienm IN hierarchies AND version IN versions ) ( h-label ) ).
        APPEND VALUE #( key_date       = key_date
                        characteristic = listed-name
                        test           = `HIERARCHIES`
                        status         = c_status-ok
                        rows           = lines( shown )
                        answer         = concat_lines_of( table = shown sep = `; ` ) ) TO result.
      ENDLOOP.
    ENDIF.

    IF tests-flat = abap_true.
      APPEND answered( VALUE #( key_date = key_date test = `TOTAL` mdx = select( `` ) ) ) TO result.
    ENDIF.
    LOOP AT list INTO DATA(characteristic).
      APPEND LINES OF probe_flat( key_date       = key_date
                                  characteristic = characteristic
                                  tests          = tests ) TO result.
      LOOP AT characteristic-hierarchies INTO DATA(hierarchy).
        APPEND LINES OF probe_hierarchy( key_date       = key_date
                                         characteristic = characteristic-name
                                         hierarchy      = hierarchy
                                         tests          = tests ) TO result.
      ENDLOOP.
    ENDLOOP.
    IF tests-combined = abap_true.
      LOOP AT list INTO DATA(rows_of).
        LOOP AT list INTO DATA(filter_of) WHERE name <> rows_of-name.
          APPEND LINES OF probe_combined( key_date  = key_date
                                          rows_of   = rows_of
                                          filter_of = filter_of
                                          leaves    = tests-combine_leaves ) TO result.
        ENDLOOP.
      ENDLOOP.
    ENDIF.
    IF tests-pairs = abap_true AND lines( characteristics ) >= 2.
      DATA(first_name) = characteristics[ 1 ].
      DATA(second_name) = characteristics[ 2 ].
      LOOP AT pairs INTO DATA(pair).
        APPEND answered( VALUE #( key_date       = key_date
                                  characteristic = first_name
                                  hierarchy      = |[{ first_name }]|
                                  test           = `PAIR`
                                  node           = pair-first
                                  node_type      = `VALUE`
                                  filter_char    = second_name
                                  filter_node    = pair-second
                                  mdx            = select( rows   = ``
                                                           slicer = |[{ first_name }].[{ pair-first }], | &&
                                                                    |[{ second_name }].[{ pair-second }]| ) ) )
          TO result.
      ENDLOOP.
    ENDIF.
    " a crossjoin is the same both ways round: each characteristic with each later one
    IF tests-crossjoin = abap_true.
      LOOP AT list INTO DATA(left).
        DATA(following) = sy-tabix + 1.
        LOOP AT list INTO DATA(right) FROM following.
          APPEND LINES OF probe_crossjoin( key_date   = key_date
                                           rows_of    = left
                                           cross_with = right ) TO result.
        ENDLOOP.
      ENDLOOP.
    ENDIF.
    analysis_user( sy-uname ).
  ENDMETHOD.

  METHOD analysis_user.
    IF name <> sy-uname OR user <> sy-uname.
      CALL FUNCTION 'RSEC_SET_USERNAME'
        EXPORTING
          i_username = name.
    ENDIF.
    CALL FUNCTION 'RSEC_GET_USERNAME'
      IMPORTING
        e_username = result.
  ENDMETHOD.

  METHOD probe_flat.
    DATA(flat) = |[{ characteristic-name }]|.
    DATA(row) = VALUE ty_result( key_date       = key_date
                                 characteristic = characteristic-name
                                 hierarchy      = flat ).
    IF tests-flat = abap_true.
      row-test = `MEMBERS`.
      row-mdx = select( |\{{ flat }.Members\}| ).
      APPEND answered( row ) TO result.
    ENDIF.
    IF tests-non_empty = abap_true.
      row-test = `MEMBERS NE`.
      row-mdx = select( |NON EMPTY \{{ flat }.Members\}| ).
      APPEND answered( row ) TO result.
    ENDIF.
    IF tests-levels = abap_true.
      APPEND LINES OF probe_levels( row = row levels = characteristic-levels ) TO result.
    ENDIF.
    row-node_type = `VALUE`.
    LOOP AT characteristic-values INTO DATA(value).
      row-node = value.
      IF tests-flat = abap_true.
        row-test = `SLICER`.
        row-mdx = select( rows   = ``
                          slicer = |{ flat }.[{ value }]| ).
        APPEND answered( row ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD probe_levels.
    DATA(level_row) = row.
    level_row-test = `LEVEL`.
    level_row-node_type = `LEVEL`.
    LOOP AT levels INTO DATA(level).
      level_row-node = level-name.
      level_row-level = level-number.
      level_row-mdx = select( |\{{ level-unique }.Members\}| ).
      APPEND answered( level_row ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD probe_crossjoin.
    " the row sets of each characteristic: its members and the members of each of its hierarchies
    DATA(left_sets) = VALUE string_table( ( |[{ rows_of-name }]| ) ).
    DATA(left_labels) = left_sets.
    LOOP AT rows_of-hierarchies INTO DATA(hierarchy).
      APPEND hierarchy-unique TO left_sets.
      APPEND hierarchy-label TO left_labels.
    ENDLOOP.
    DATA(right_sets) = VALUE string_table( ( |[{ cross_with-name }]| ) ).
    DATA(right_labels) = right_sets.
    LOOP AT cross_with-hierarchies INTO hierarchy.
      APPEND hierarchy-unique TO right_sets.
      APPEND hierarchy-label TO right_labels.
    ENDLOOP.

    LOOP AT left_sets INTO DATA(left_set).
      DATA(left_index) = sy-tabix.
      DATA(left_label) = left_labels[ left_index ].
      LOOP AT right_sets INTO DATA(right_set).
        IF left_index > 1 AND sy-tabix > 1.
          CONTINUE.
        ENDIF.
        DATA(row) = VALUE ty_result( key_date         = key_date
                                     characteristic   = rows_of-name
                                     hierarchy        = left_label
                                     filter_char      = cross_with-name
                                     filter_hierarchy = right_labels[ sy-tabix ] ).
        DATA(crossjoin) = |CrossJoin(\{{ left_set }.Members\}, \{{ right_set }.Members\})|.
        row-test = `CROSSJOIN`.
        row-mdx = select( crossjoin ).
        APPEND answered( row ) TO result.
        row-test = `CROSSJOIN NE`.
        row-mdx = select( |NON EMPTY { crossjoin }| ).
        APPEND answered( row ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD probe_hierarchy.
    DATA(row) = VALUE ty_result( key_date       = key_date
                                 characteristic = characteristic
                                 hierarchy      = hierarchy-label
                                 valid_to       = hierarchy-dateto ).
    IF tests-members = abap_true.
      row-test = `MEMBERS`.
      row-mdx = select( |\{{ hierarchy-unique }.Members\}| ).
      APPEND answered( row ) TO result.
    ENDIF.
    IF tests-non_empty = abap_true.
      row-test = `MEMBERS NE`.
      row-mdx = select( |NON EMPTY \{{ hierarchy-unique }.Members\}| ).
      APPEND answered( row ) TO result.
    ENDIF.
    IF tests-levels = abap_true.
      APPEND LINES OF probe_levels( row = row levels = hierarchy-levels ) TO result.
    ENDIF.

    LOOP AT hierarchy-nodes INTO DATA(node).
      DATA(member) = node_name( hierarchy      = hierarchy-unique
                                characteristic = characteristic
                                iobjnm         = node-iobjnm
                                nodename       = node-nodename ).
      row-node = node-nodename.
      row-node_type = COND #( WHEN node-iobjnm = characteristic THEN `LEAF` ELSE `TEXT NODE` ).
      row-level = node-tlevel.
      IF tests-slicer = abap_true.
        row-test = `SLICER`.
        row-mdx = select( rows = `` slicer = member ).
        APPEND answered( row ) TO result.
      ENDIF.
      IF tests-rows = abap_true.
        row-test = `ROWS`.
        row-mdx = select( |\{{ member }\}| ).
        APPEND answered( row ) TO result.
      ENDIF.
      IF tests-children = abap_true AND node-iobjnm <> characteristic.
        row-test = `CHILDREN`.
        row-mdx = select( |\{{ member }.Children\}| ).
        APPEND answered( row ) TO result.
      ENDIF.
      IF tests-non_empty = abap_true AND node-iobjnm <> characteristic.
        row-test = `CHILDREN NE`.
        row-mdx = select( |NON EMPTY \{{ member }.Children\}| ).
        APPEND answered( row ) TO result.
      ENDIF.
      IF tests-parent = abap_true AND node-parentid <> 0.
        row-test = `PARENT`.
        row-mdx = select( |\{{ member }.Parent\}| ).
        APPEND answered( row ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD probe_combined.
    " the restrictions on the other characteristic: its values, the text nodes (and leaves) of its hierarchies
    DATA filters TYPE ty_filters.
    DATA(flat) = |[{ filter_of-name }]|.
    LOOP AT filter_of-values INTO DATA(value).
      APPEND VALUE #( hierarchy = flat node = value member = |{ flat }.[{ value }]| ) TO filters.
    ENDLOOP.
    LOOP AT filter_of-hierarchies INTO DATA(hierarchy).
      LOOP AT hierarchy-nodes INTO DATA(node).
        IF leaves = abap_false AND node-iobjnm = filter_of-name.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( hierarchy = hierarchy-label
                        node      = node-nodename
                        member    = node_name( hierarchy      = hierarchy-unique
                                               characteristic = filter_of-name
                                               iobjnm         = node-iobjnm
                                               nodename       = node-nodename ) ) TO filters.
      ENDLOOP.
    ENDLOOP.

    " the row sets of the one characteristic: its members and the members of each of its hierarchies
    DATA(row_sets) = VALUE string_table( ( |[{ rows_of-name }]| ) ).
    DATA(labels) = VALUE string_table( ( |[{ rows_of-name }]| ) ).
    LOOP AT rows_of-hierarchies INTO hierarchy.
      APPEND hierarchy-unique TO row_sets.
      APPEND hierarchy-label TO labels.
    ENDLOOP.

    LOOP AT row_sets INTO DATA(row_set).
      DATA(label) = labels[ sy-tabix ].
      LOOP AT filters INTO DATA(filter).
        APPEND answered( VALUE #( key_date         = key_date
                                  characteristic   = rows_of-name
                                  hierarchy        = label
                                  test             = `COMBINED`
                                  filter_char      = filter_of-name
                                  filter_hierarchy = filter-hierarchy
                                  filter_node      = filter-node
                                  mdx              = select( rows   = |\{{ row_set }.Members\}|
                                                             slicer = filter-member ) ) ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD answered.
    result = row.
    DATA(answer) = execute( row-mdx ).
    result-status = answer-status.
    result-rows = answer-rows.
    result-answer = answer-answer.
    result-message = answer-message.
    result-cells = answer-cells.
  ENDMETHOD.

  METHOD read_characteristic.
    result-name = name.
    result-values = values( name ).
    result-levels = mdx_levels( characteristic = name
                                hierarchy      = |[{ name }]| ).
    LOOP AT mdx_hierarchies( name ) INTO DATA(hierarchy) WHERE hienm IN hierarchies AND version IN versions.
      hierarchy-nodes = nodes( characteristic = name
                               hieid          = hierarchy-hieid ).
      hierarchy-levels = mdx_levels( characteristic = name
                                     hierarchy      = hierarchy-unique ).
      APPEND hierarchy TO result-hierarchies.
    ENDLOOP.
  ENDMETHOD.

  METHOD values.
    TYPES ty_value TYPE c LENGTH 60.
    DATA keys TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.
    DATA(table) = |/BIC/S{ characteristic }|.
    DATA(column) = |/BIC/{ characteristic }|.
    SELECT (column)
      FROM (table)
      WHERE sid > 0
      ORDER BY (column)
      INTO TABLE @keys.
    LOOP AT keys INTO DATA(key) WHERE table_line IS NOT INITIAL.
      APPEND |{ key }| TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD mdx_hierarchies.
    DATA hierarchies TYPE STANDARD TABLE OF bapi6110hry.
    DATA return TYPE bapiret2.
    DATA cat_nam TYPE bapi6110hry-cat_nam VALUE '$INFOCUBE'.
    DATA cube_nam TYPE bapi6110hry-cube_nam.
    DATA dim_unam TYPE bapi6110hry-dim_unam.
    cube_nam = |[{ cube }]|.
    dim_unam = |[{ characteristic }]|.
    CALL FUNCTION 'BAPI_MDPROVIDER_GET_HIERARCHYS'
      EXPORTING
        cat_nam     = cat_nam
        cube_nam    = cube_nam
        dim_unam    = dim_unam
      IMPORTING
        return      = return
      TABLES
        hierarchies = hierarchies.
    LOOP AT hierarchies INTO DATA(hierarchy) WHERE hry_nam <> characteristic.
      " the name is the hierarchy name (30), the version (3, blank if not version dependent) and the end of the
      " slice's validity (8)
      DATA(entry) = VALUE ty_hierarchy( hienm   = hierarchy-hry_nam(30)
                                        version = hierarchy-hry_nam+30(3)
                                        dateto  = hierarchy-hry_nam+33(8)
                                        unique  = hierarchy-hry_unam ).
      entry-label = condense( |{ entry-hienm } { entry-version }| ).
      SELECT SINGLE hieid FROM rshiedir
        WHERE iobjnm = @characteristic
          AND hienm = @entry-hienm
          AND version = @entry-version
          AND dateto = @entry-dateto
          AND objvers = 'A'
        INTO @entry-hieid.
      APPEND entry TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD mdx_levels.
    DATA levels TYPE STANDARD TABLE OF bapi6110lvl.
    DATA return TYPE bapiret2.
    DATA cat_nam TYPE bapi6110lvl-cat_nam VALUE '$INFOCUBE'.
    DATA cube_nam TYPE bapi6110lvl-cube_nam.
    DATA dim_unam TYPE bapi6110lvl-dim_unam.
    DATA hry_unam TYPE bapi6110lvl-hry_unam.
    cube_nam = |[{ cube }]|.
    dim_unam = |[{ characteristic }]|.
    hry_unam = hierarchy.
    CALL FUNCTION 'BAPI_MDPROVIDER_GET_LEVELS'
      EXPORTING
        cat_nam  = cat_nam
        cube_nam = cube_nam
        dim_unam = dim_unam
        hry_unam = hry_unam
      IMPORTING
        return   = return
      TABLES
        levels   = levels.
    LOOP AT levels INTO DATA(level).
      APPEND VALUE #( name   = condense( |{ level-lvl_nam }| )
                      unique = |{ level-lvl_unam }|
                      number = level-lvl_number ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD nodes.
    DATA(table) = |/BIC/H{ characteristic }|.
    SELECT nodeid, iobjnm, nodename, tlevel, parentid
      FROM (table)
      WHERE hieid = @hieid
        AND objvers = 'A'
      ORDER BY nodeid ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @result.
  ENDMETHOD.

  METHOD select.
    result = |SELECT \{[Measures].[{ measure }]\} ON 0|.
    IF rows IS NOT INITIAL.
      result = |{ result }, { rows } ON 1|.
    ENDIF.
    result = |{ result } FROM [{ cube }]|.
    IF slicer IS NOT INITIAL.
      result = |{ result } WHERE ({ slicer })|.
    ENDIF.
  ENDMETHOD.

  METHOD execute.
    DATA lines TYPE STANDARD TABLE OF bapi6111mdx.
    DATA datasetid TYPE bapi6111gen-obj_handle.
    DATA return TYPE bapiret2.

    LOOP AT command_lines( mdx ) INTO DATA(line).
      APPEND VALUE #( line = line ) TO lines.
    ENDLOOP.
    CALL FUNCTION 'BAPI_MDDATASET_CREATE_OBJECT'
      IMPORTING
        return       = return
        datasetid    = datasetid
      TABLES
        command_text = lines.
    IF return-type CA 'EAX'.
      result = failed( return = return step = `create` ).
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAPI_MDDATASET_SELECT_DATA'
      EXPORTING
        datasetid = datasetid
      IMPORTING
        return    = return.
    IF return-type CA 'EAX'.
      result = failed( return = return step = `execute` ).
    ELSE.
      answer_text( EXPORTING datasetid = datasetid
                             has_rows  = xsdbool( mdx CS ` ON 1` )
                   CHANGING  answer    = result ).
      " BW answers some statements with a warning or an information and no rows: kept as the message
      IF result-message IS INITIAL AND return-type CA 'WI' AND return-message IS NOT INITIAL.
        result-message = |execute: { return-type } { return-id } { return-number }: { return-message }|.
      ENDIF.
    ENDIF.

    CALL FUNCTION 'BAPI_MDDATASET_DELETE_OBJECT'
      EXPORTING
        datasetid = datasetid
      IMPORTING
        return    = return.
  ENDMETHOD.

  METHOD answer_text.
    DATA members TYPE STANDARD TABLE OF bapi6111mpp.
    DATA option_keys TYPE STANDARD TABLE OF bapi6111opk.
    DATA option_values TYPE STANDARD TABLE OF bapi6111opv.
    DATA cell_data TYPE STANDARD TABLE OF bapi6111cd.
    DATA cell_props TYPE STANDARD TABLE OF bapi6111prn.
    DATA cell_prop_names TYPE STANDARD TABLE OF bapi6110prpnam.
    DATA return TYPE bapiret2.
    DATA axis TYPE bapi6111axi-axis VALUE 1.
    IF has_rows = abap_true.
      CALL FUNCTION 'BAPI_MDDATASET_GET_AXIS_DATA'
        EXPORTING
          datasetid          = datasetid
          axis               = axis
        IMPORTING
          return             = return
        TABLES
          mndtry_prptys      = members
          option_prptys_keys = option_keys
          option_prptys_vals = option_values.
      IF return-type CA 'EAX'.
        answer = failed( return = return step = `axis` ).
        RETURN.
      ENDIF.
    ENDIF.
    " the rows: per tuple its members in the order of the axis' hierarchies
    SORT members STABLE BY tuple_ordinal.
    DATA(row_count) = COND i( WHEN has_rows = abap_true
                              THEN COND #( WHEN members IS INITIAL THEN 0
                                           ELSE members[ lines( members ) ]-tuple_ordinal + 1 )
                              ELSE 1 ).
    IF row_count > 0.
      DATA start_cell TYPE bapi6111cd-cell_ordinal VALUE 0.
      DATA end_cell TYPE bapi6111cd-cell_ordinal.
      end_cell = row_count - 1.
      CALL FUNCTION 'BAPI_MDDATASET_GET_CELL_DATA'
        EXPORTING
          datasetid       = datasetid
          start_cell      = start_cell
          end_cell        = end_cell
        IMPORTING
          return          = return
        TABLES
          cell_data       = cell_data
          cell_props      = cell_props
          cell_prop_names = cell_prop_names.
      IF return-type CA 'EAX'.
        answer = failed( return = return step = `cells` ).
        RETURN.
      ENDIF.
    ENDIF.

    DATA cell TYPE ty_cell.
    DATA texts TYPE string_table.
    DO row_count TIMES.
      DATA(ordinal) = sy-index - 1.
      CLEAR cell.
      LOOP AT members INTO DATA(member) WHERE tuple_ordinal = ordinal.
        APPEND |{ member-mem_unam }| TO cell-members.
        APPEND condense( |{ member-mem_cap }| ) TO cell-captions.
      ENDLOOP.
      READ TABLE cell_data INTO DATA(value) WITH KEY cell_ordinal = ordinal.
      IF sy-subrc = 0.
        cell-value = condense( |{ value-value }| ).
        cell-status = condense( |{ value-cell_status }| ).
      ENDIF.
      APPEND cell TO answer-cells.
      DATA(text) = condense( |{ value-formatted_value }| ).
      IF cell-status IS NOT INITIAL.
        text = |{ text } (status { cell-status })|.
      ENDIF.
      APPEND COND string( WHEN has_rows = abap_false THEN text
                          ELSE |{ concat_lines_of( table = cell-captions sep = ` | ` ) } = { text }| ) TO texts.
      CLEAR value.
    ENDDO.
    answer-rows = lines( texts ).
    answer-status = COND #( WHEN texts IS INITIAL THEN c_status-empty ELSE c_status-ok ).
    answer-answer = concat_lines_of( table = texts sep = `; ` ).
    IF strlen( answer-answer ) > c_max_answer.
      answer-answer = |{ substring( val = answer-answer len = c_max_answer ) }...|.
    ENDIF.
  ENDMETHOD.

  METHOD failed.
    result-message = |{ step }: { return-id } { return-number }: { return-message }|.
    " BW's analysis authorization messages are of class EYE or speak of authorization; a value the user may not see
    " is unknown to BW (BRAINOLAPAPI 510, Value ... for characteristic ... unknown)
    IF return-id = 'EYE' OR return-message CS 'authoriz'.
      result-status = c_status-no_auth.
    ELSEIF return-id = 'BRAINOLAPAPI' AND return-number = '510'.
      result-status = c_status-unknown.
    ELSE.
      result-status = c_status-error.
    ENDIF.
  ENDMETHOD.

  METHOD authorizations.
    TYPES ty_auth_range TYPE RANGE OF rsauth.
    TYPES ty_iobjnm_range TYPE RANGE OF rsiobjnm.
    DATA(restricted) = VALUE ty_iobjnm_range( FOR c IN characteristics ( sign = 'I' option = 'EQ' low = c ) ).

    " the authorizations that restrict one of the characteristics, by value or by hierarchy, and 0BI_ALL; BW keeps the
    " values in RSECVAL_STRING and RSECHIE_STRING (RSECVAL and RSECHIE hold only 0BI_ALL on this release)
    SELECT DISTINCT tctauth FROM rsecval_string
      WHERE objvers = 'A'
        AND ( tctiobjnm IN @restricted OR tctauth = '0BI_ALL' )
      INTO TABLE @DATA(by_value).
    SELECT DISTINCT tctauth FROM rsechie_string
      WHERE objvers = 'A'
        AND tctiobjnm IN @restricted
      INTO TABLE @DATA(by_hierarchy).
    DATA(auths) = VALUE ty_auth_range( FOR v IN by_value ( sign = 'I' option = 'EQ' low = v-tctauth ) ).
    LOOP AT by_hierarchy INTO DATA(h).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = h-tctauth ) TO auths.
    ENDLOOP.
    IF auths IS INITIAL.
      RETURN.
    ENDIF.

    SELECT tctauth, tctiobjnm, tctsign, tctoption, tctlow, tcthigh
      FROM rsecval_string
      WHERE objvers = 'A'
        AND tctauth IN @auths
      ORDER BY tctauth ASCENDING, tctiobjnm ASCENDING, tctlow ASCENDING
      INTO TABLE @DATA(values).
    LOOP AT values INTO DATA(value).
      APPEND VALUE #( auth    = value-tctauth
                      kind    = 'VALUE'
                      details = |{ value-tctiobjnm } { value-tctsign } { value-tctoption } { value-tctlow }{
                                  COND string( WHEN value-tcthigh IS NOT INITIAL THEN | - { value-tcthigh }| ) }| )
             TO result.
    ENDLOOP.

    SELECT tctauth, tctiobjnm, tcthienm, tcthievers, tcthiedate, tctniobjnm, tctnode, tctatype, tctacompm, tcttlevel
      FROM rsechie_string
      WHERE objvers = 'A'
        AND tctauth IN @auths
      ORDER BY tctauth ASCENDING, tctiobjnm ASCENDING, tcthienm ASCENDING, tctnode ASCENDING
      INTO TABLE @DATA(hierarchy_values).
    LOOP AT hierarchy_values INTO DATA(hierarchy_value).
      APPEND VALUE #(
        auth    = hierarchy_value-tctauth
        kind    = 'HIERARCHY'
        details = |{ hierarchy_value-tctiobjnm } { hierarchy_value-tcthienm } version {
                    hierarchy_value-tcthievers } date { hierarchy_value-tcthiedate DATE = ISO } node {
                    hierarchy_value-tctnode } ({ hierarchy_value-tctniobjnm }) type { hierarchy_value-tctatype
                    } level { hierarchy_value-tcttlevel } validity { hierarchy_value-tctacompm }| )
        TO result.
    ENDLOOP.
    SORT result STABLE BY auth kind.

    SELECT auth FROM rsecuserauth
      WHERE uname = @user
      INTO TABLE @DATA(direct).
    LOOP AT result ASSIGNING FIELD-SYMBOL(<authorization>).
      AUTHORITY-CHECK OBJECT 'S_RS_AUTH' FOR USER user ID 'BIAUTH' FIELD <authorization>-auth.
      IF sy-subrc = 0 OR line_exists( direct[ auth = <authorization>-auth ] ).
        <authorization>-assigned = abap_true.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD node_name.
    DATA node32 TYPE c LENGTH 32.
    IF iobjnm = characteristic.
      result = |{ hierarchy }.[{ nodename }]|.
    ELSE.
      node32 = nodename.
      CONCATENATE hierarchy '.[' node32 iobjnm ']' INTO result RESPECTING BLANKS.
    ENDIF.
  ENDMETHOD.

  METHOD command_lines.
    CONSTANTS width TYPE i VALUE 75.
    DATA(offset) = 0.
    WHILE offset < strlen( mdx ).
      APPEND substring( val = mdx off = offset len = nmin( val1 = width val2 = strlen( mdx ) - offset ) ) TO result.
      offset = offset + width.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
