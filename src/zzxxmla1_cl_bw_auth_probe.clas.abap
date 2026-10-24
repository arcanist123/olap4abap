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
"! (BAPI_MDDATASET_*) as the current user and records per query whether BW answers, what, or which message it gives.
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
"!   hierarchies) with each value and each text node of the other as slicer (leaves too on request).
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
           END OF ty_tests.
    " a query and BW's answer; filter_* is the restriction on the other characteristic of a combined query
    TYPES: BEGIN OF ty_result,
             key_date         TYPE d,
             characteristic   TYPE rsiobjnm,
             hierarchy        TYPE c LENGTH 40,
             valid_to         TYPE d,
             test             TYPE c LENGTH 10,
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
           END OF ty_result.
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
                 error   TYPE c LENGTH 8 VALUE 'ERROR',
               END OF c_status.

    "! @parameter characteristics | the authorization-relevant characteristics; ZCLDOC and ZCLDIAG if none
    METHODS constructor
      IMPORTING cube            TYPE string DEFAULT `$ZCLVISITA`
                characteristics TYPE ty_characteristics OPTIONAL
                measure         TYPE string DEFAULT `ZCLVISNO`.

    "! Runs the queries once per key date, as the current user; the key date is reset afterwards.
    METHODS run
      IMPORTING key_dates     TYPE ty_dates
                hierarchies   TYPE ty_hienm_range OPTIONAL
                versions      TYPE ty_version_range OPTIONAL
                tests         TYPE ty_tests
      RETURNING VALUE(result) TYPE ty_results.

    "! The analysis authorizations that restrict one of the characteristics (value and hierarchy authorizations,
    "! RSECVAL and RSECHIE) with all their lines, and 0BI_ALL, each with whether the current user has it (S_RS_AUTH or
    "! RSECADMIN's direct assignment).
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
    " a hierarchy as BW's MDX shows it at the key date, with the nodes of its slice
    TYPES: BEGIN OF ty_hierarchy,
             hienm   TYPE rshienm,
             version TYPE rsversion,
             dateto  TYPE d,
             hieid   TYPE rshieid,
             unique  TYPE string,
             label   TYPE string,
             nodes   TYPE ty_nodes,
           END OF ty_hierarchy.
    TYPES ty_hierarchies TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    " a characteristic at the key date: its values and the hierarchies BW's MDX shows
    TYPES: BEGIN OF ty_characteristic,
             name        TYPE rsiobjnm,
             values      TYPE string_table,
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
           END OF ty_answer.

    CONSTANTS c_max_answer TYPE i VALUE 1000.

    DATA cube TYPE string.
    DATA characteristics TYPE ty_characteristics.
    DATA measure TYPE string.

    METHODS probe_key_date
      IMPORTING key_date      TYPE d
                hierarchies   TYPE ty_hienm_range
                versions      TYPE ty_version_range
                tests         TYPE ty_tests
      RETURNING VALUE(result) TYPE ty_results.
    METHODS probe_flat
      IMPORTING key_date       TYPE d
                characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_results.
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
    METHODS answer_text
      IMPORTING datasetid TYPE bapi6111gen-obj_handle
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
                                      children = abap_true parent = abap_true combined = abap_true ) )
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
  ENDMETHOD.

  METHOD run.
    LOOP AT key_dates INTO DATA(key_date).
      APPEND LINES OF probe_key_date( key_date    = key_date
                                      hierarchies = hierarchies
                                      versions    = versions
                                      tests       = tests ) TO result.
    ENDLOOP.
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

    DATA list TYPE ty_characteristic_list.
    LOOP AT characteristics INTO DATA(name).
      APPEND read_characteristic( name        = name
                                  hierarchies = hierarchies
                                  versions    = versions ) TO list.
    ENDLOOP.

    IF tests-flat = abap_true.
      APPEND answered( VALUE #( key_date = key_date test = `TOTAL` mdx = select( `` ) ) ) TO result.
    ENDIF.
    LOOP AT list INTO DATA(characteristic).
      IF tests-flat = abap_true.
        APPEND LINES OF probe_flat( key_date       = key_date
                                    characteristic = characteristic ) TO result.
      ENDIF.
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
  ENDMETHOD.

  METHOD probe_flat.
    DATA(flat) = |[{ characteristic-name }]|.
    APPEND answered( VALUE #( key_date       = key_date
                              characteristic = characteristic-name
                              hierarchy      = flat
                              test           = `MEMBERS`
                              mdx            = select( |\{{ flat }.Members\}| ) ) ) TO result.
    LOOP AT characteristic-values INTO DATA(value).
      APPEND answered( VALUE #( key_date       = key_date
                                characteristic = characteristic-name
                                hierarchy      = flat
                                test           = `SLICER`
                                node           = value
                                node_type      = `VALUE`
                                mdx            = select( rows   = ``
                                                         slicer = |{ flat }.[{ value }]| ) ) ) TO result.
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
  ENDMETHOD.

  METHOD read_characteristic.
    result-name = name.
    result-values = values( name ).
    LOOP AT mdx_hierarchies( name ) INTO DATA(hierarchy) WHERE hienm IN hierarchies AND version IN versions.
      hierarchy-nodes = nodes( characteristic = name
                               hieid          = hierarchy-hieid ).
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
                   CHANGING  answer    = result ).
    ENDIF.

    CALL FUNCTION 'BAPI_MDDATASET_DELETE_OBJECT'
      EXPORTING
        datasetid = datasetid
      IMPORTING
        return    = return.
  ENDMETHOD.

  METHOD answer_text.
    DATA header TYPE STANDARD TABLE OF bapi6111fsd.
    DATA data TYPE STANDARD TABLE OF bapi6111fsd.
    DATA return TYPE bapiret2.
    CALL FUNCTION 'BAPI_MDDATASET_GET_FLAT_DATA'
      EXPORTING
        datasetid = datasetid
      IMPORTING
        return    = return
      TABLES
        header    = header
        data      = data.
    IF return-type CA 'EAX'.
      answer = failed( return = return step = `read` ).
      RETURN.
    ENDIF.

    " a row is its last non-empty caption and the value of its last column, the measure
    DATA(last_column) = lines( header ) - 1.
    DATA caption TYPE string.
    DATA texts TYPE string_table.
    LOOP AT data INTO DATA(cell).
      DATA(text) = condense( |{ cell-data }| ).
      IF cell-column = 0.
        CLEAR caption.
      ENDIF.
      IF cell-column < last_column.
        IF text IS NOT INITIAL.
          caption = text.
        ENDIF.
        CONTINUE.
      ENDIF.
      IF cell-cell_status IS NOT INITIAL.
        text = |{ text } (status { cell-cell_status })|.
      ENDIF.
      APPEND COND string( WHEN last_column = 0 THEN text ELSE |{ caption } = { text }| ) TO texts.
    ENDLOOP.
    answer-rows = lines( texts ).
    answer-status = COND #( WHEN texts IS INITIAL THEN c_status-empty ELSE c_status-ok ).
    answer-answer = concat_lines_of( table = texts sep = `; ` ).
    IF strlen( answer-answer ) > c_max_answer.
      answer-answer = |{ substring( val = answer-answer len = c_max_answer ) }...|.
    ENDIF.
  ENDMETHOD.

  METHOD failed.
    result-message = |{ step }: { return-id } { return-number }: { return-message }|.
    " BW's analysis authorization messages are of class EYE or speak of authorization
    IF return-id = 'EYE' OR return-message CS 'authoriz'.
      result-status = c_status-no_auth.
    ELSE.
      result-status = c_status-error.
    ENDIF.
  ENDMETHOD.

  METHOD authorizations.
    TYPES ty_auth_range TYPE RANGE OF rsauth.
    TYPES ty_iobjnm_range TYPE RANGE OF rsiobjnm.
    DATA(restricted) = VALUE ty_iobjnm_range( FOR c IN characteristics ( sign = 'I' option = 'EQ' low = c ) ).

    " the authorizations that restrict one of the characteristics, by value or by hierarchy, and 0BI_ALL
    SELECT DISTINCT tctauth FROM rsecval
      WHERE objvers = 'A'
        AND ( tctiobjnm IN @restricted OR tctauth = '0BI_ALL' )
      INTO TABLE @DATA(by_value).
    SELECT DISTINCT tctauth FROM rsechie
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
      FROM rsecval
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
      FROM rsechie
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
      WHERE uname = @sy-uname
      INTO TABLE @DATA(direct).
    LOOP AT result ASSIGNING FIELD-SYMBOL(<authorization>).
      AUTHORITY-CHECK OBJECT 'S_RS_AUTH' ID 'BIAUTH' FIELD <authorization>-auth.
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
