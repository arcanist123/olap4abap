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
"! The probe's queries answered by the authorization check (docs/next-steps.md, Now: analysis authorisations, step 4):
"! the queries ZZXXMLA1_CL_BW_AUTH_PROBE asks BW at a key date, named as its result rows name them, each translated
"! into the selection it makes and answered by ZZXXMLA1_CL_BW_AUTH's check for the user: ALLOWED, EMPTY (allowed with
"! nothing to show: the children of a node that may not be expanded, the parent of a top node, a level without a
"! visible node, a level of a hierarchy without a line of the user), NO AUTH or UNKNOWN; for a set of a restricted
"! hierarchy also the members it shows. scripts/auth_check_test.py compares the answers with BW's in reference/auth/.
"! The selection is the one BW makes (docs/mvp-scope.md, BW's rules): a slicer and the node a query starts from are
"! named members, the members of a set are not, a characteristic the query does not name is aggregated. A hierarchy's
"! members are, where the user has a line on it, the visible nodes and the children of the visible nodes that may not
"! be expanded (which the check refuses: .Members of such a hierarchy is refused), else all its nodes (allowed with *,
"! refused as a hierarchy without a line).
CLASS zzxxmla1_cl_bw_auth_queries DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES ty_iobjnms TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
    "! a hierarchy (name and version) with its slice valid at the key date
    TYPES: BEGIN OF ty_hierarchy,
             hienm   TYPE rshienm,
             version TYPE rsversion,
             slice   TYPE zzxxmla1_cl_bw_auth=>ty_slice,
           END OF ty_hierarchy.
    TYPES ty_hierarchies TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    "! a characteristic as the probe asks it: its values (of its SID table, without the initial one) and its
    "! hierarchies valid at the key date
    TYPES: BEGIN OF ty_characteristic,
             iobjnm      TYPE rsiobjnm,
             values      TYPE string_table,
             hierarchies TYPE ty_hierarchies,
           END OF ty_characteristic.
    TYPES ty_characteristics TYPE STANDARD TABLE OF ty_characteristic WITH EMPTY KEY.
    "! a value of the first characteristic and one of the second (the probe's test pairs)
    TYPES: BEGIN OF ty_pair,
             first  TYPE string,
             second TYPE string,
           END OF ty_pair.
    TYPES ty_pairs TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY.
    "! a query, its fields as the probe's result rows name them, and the check's answer; restricted: members are the
    "! members of a restricted hierarchy the query shows (the probe's member keys: a leaf's key, a node's name padded
    "! to 32 and its InfoObject, blanks collapsed); answer: the hierarchies of the test HIERARCHIES
    TYPES: BEGIN OF ty_result,
             characteristic   TYPE rsiobjnm,
             hierarchy        TYPE string,
             test             TYPE string,
             node             TYPE string,
             filter_char      TYPE rsiobjnm,
             filter_hierarchy TYPE string,
             filter_node      TYPE string,
             status           TYPE c LENGTH 8,
             reason           TYPE c LENGTH 12,
             message          TYPE string,
             restricted       TYPE abap_bool,
             members          TYPE string_table,
             answer           TYPE string,
           END OF ty_result.
    TYPES ty_results TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CONSTANTS c_empty TYPE c LENGTH 8 VALUE 'EMPTY'.

    "! The queries on the provider at the key date for the user, the characteristics read from BW.
    "! @parameter characteristics | the probe's: ZCLDOC and ZCLDIAG if none
    CLASS-METHODS read
      IMPORTING !user           TYPE xubname
                provider        TYPE csequence DEFAULT `ZCLVISITA`
                characteristics TYPE ty_iobjnms OPTIONAL
                key_date        TYPE d
      RETURNING VALUE(result)   TYPE REF TO zzxxmla1_cl_bw_auth_queries
      RAISING   zzxxmla1_cx_bw_provider.
    "! The queries on given characteristics for a region, for the unit tests.
    CLASS-METHODS create
      IMPORTING region          TYPE REF TO zzxxmla1_cl_bw_auth
                characteristics TYPE ty_characteristics
      RETURNING VALUE(result)   TYPE REF TO zzxxmla1_cl_bw_auth_queries.

    "! Every query of the probe with the check's answer: the hierarchies listed, the total, per characteristic its
    "! members, levels and values, per hierarchy its members, levels and per node the node as slicer, on the rows, its
    "! children and its parent, each row set of one characteristic with each value and text node of the other as
    "! slicer, the pairs, and the crossjoins of the first characteristic's row sets with the second's (one side flat).
    METHODS run
      IMPORTING pairs         TYPE ty_pairs OPTIONAL
      RETURNING VALUE(result) TYPE ty_results.
    "! The authorizations that apply to the provider.
    METHODS applying
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_auths.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! a node of a hierarchy as the user sees it: depth the level BW shows it on (0 the top), top: its parent is not
    "! shown
    TYPES: BEGIN OF ty_view_node,
             iobjnm        TYPE rsiobjnm,
             name          TYPE string,
             depth         TYPE i,
             expandable    TYPE abap_bool,
             top           TYPE abap_bool,
             parent_iobjnm TYPE rsiobjnm,
             parent_name   TYPE string,
           END OF ty_view_node.
    TYPES ty_view_nodes TYPE STANDARD TABLE OF ty_view_node WITH EMPTY KEY.
    "! a hierarchy as the user sees it: restricted to the visible nodes where the user has a line on it and not all of
    "! it, else all its nodes; levels: BW's levels, as many as the slice's deepest node
    TYPES: BEGIN OF ty_view,
             iobjnm     TYPE rsiobjnm,
             label      TYPE string,
             hienm      TYPE rshienm,
             version    TYPE rsversion,
             all        TYPE abap_bool,
             lines      TYPE abap_bool,
             restricted TYPE abap_bool,
             levels     TYPE i,
             nodes      TYPE ty_view_nodes,
             slice      TYPE zzxxmla1_cl_bw_auth=>ty_slice,
           END OF ty_view.
    TYPES ty_views TYPE STANDARD TABLE OF ty_view WITH EMPTY KEY.
    TYPES ty_members TYPE STANDARD TABLE OF zzxxmla1_cl_bw_auth=>ty_member WITH EMPTY KEY.
    "! a row set: the members of a characteristic's flat hierarchy or of a hierarchy, with the members it shows of a
    "! restricted one
    TYPES: BEGIN OF ty_row_set,
             label      TYPE string,
             members    TYPE ty_members,
             restricted TYPE abap_bool,
             shown      TYPE string_table,
             flat       TYPE abap_bool,
           END OF ty_row_set.
    TYPES ty_row_sets TYPE STANDARD TABLE OF ty_row_set WITH EMPTY KEY.

    DATA region TYPE REF TO zzxxmla1_cl_bw_auth.
    DATA characteristics TYPE ty_characteristics.
    DATA views TYPE ty_views.

    "! the values of a characteristic from its SID table, without the initial value, as the probe reads them
    CLASS-METHODS values
      IMPORTING iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE string_table.
    CLASS-METHODS label
      IMPORTING hienm         TYPE rshienm
                version       TYPE rsversion
      RETURNING VALUE(result) TYPE string.
    "! the probe's key of a member: a leaf's key, a node's name padded to 32 and its InfoObject, blanks collapsed
    CLASS-METHODS member_key
      IMPORTING characteristic TYPE rsiobjnm
                iobjnm         TYPE rsiobjnm
                name           TYPE csequence
      RETURNING VALUE(result)  TYPE string.

    METHODS view
      IMPORTING iobjnm        TYPE rsiobjnm
                hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE ty_view.
    "! the slice's nodes below the node of the name (and of every link to it)
    METHODS slice_children
      IMPORTING slice         TYPE zzxxmla1_cl_bw_auth=>ty_slice
                iobjnm        TYPE rsiobjnm
                name          TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_nodes.
    "! the members of a hierarchy for its .Members: the nodes the user sees and, of a restricted one, the children of a
    "! node that may not be expanded
    METHODS hierarchy_members
      IMPORTING view          TYPE ty_view
      RETURNING VALUE(result) TYPE ty_members.
    METHODS node_member
      IMPORTING view          TYPE ty_view
                iobjnm        TYPE rsiobjnm
                name          TYPE csequence
                named         TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    METHODS members_of_nodes
      IMPORTING view          TYPE ty_view
                nodes         TYPE ty_view_nodes
      RETURNING VALUE(result) TYPE ty_members.
    METHODS keys_of_nodes
      IMPORTING view          TYPE ty_view
                nodes         TYPE ty_view_nodes
      RETURNING VALUE(result) TYPE string_table.
    "! the flat hierarchy's members: the All member, the values and the value not assigned
    METHODS flat_members
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_members.
    "! the row sets of a characteristic: its flat hierarchy and each of its hierarchies
    METHODS row_sets
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_row_sets.
    "! one tuple per member of the first set (crossed with the second if given), each with the members of with
    METHODS tuples
      IMPORTING first         TYPE ty_members
                second        TYPE ty_members OPTIONAL
                !with         TYPE zzxxmla1_cl_bw_auth=>ty_tuple OPTIONAL
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_selection.
    "! the row with the check's answer: of the selection, or without a tuple of the named members (EMPTY if allowed)
    METHODS answered
      IMPORTING !row          TYPE ty_result
                selection     TYPE zzxxmla1_cl_bw_auth=>ty_selection
                named         TYPE zzxxmla1_cl_bw_auth=>ty_tuple OPTIONAL
      RETURNING VALUE(result) TYPE ty_result.
    METHODS flat_queries
      IMPORTING characteristic TYPE ty_characteristic
      RETURNING VALUE(result)  TYPE ty_results.
    METHODS hierarchy_queries
      IMPORTING view          TYPE ty_view
      RETURNING VALUE(result) TYPE ty_results.
    METHODS combined_queries
      IMPORTING rows_of       TYPE ty_characteristic
                filter_of     TYPE ty_characteristic
      RETURNING VALUE(result) TYPE ty_results.
    METHODS crossjoin_queries
      IMPORTING rows_of       TYPE ty_characteristic
                cross_with    TYPE ty_characteristic
      RETURNING VALUE(result) TYPE ty_results.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_queries IMPLEMENTATION.

  METHOD read.
    DATA list TYPE ty_characteristics.
    DATA(names) = characteristics.
    IF names IS INITIAL.
      names = VALUE #( ( 'ZCLDOC' ) ( 'ZCLDIAG' ) ).
    ENDIF.
    LOOP AT names INTO DATA(name).
      DATA(characteristic) = VALUE ty_characteristic( iobjnm = name values = values( name ) ).
      SELECT hienm, version FROM rshiedir
        WHERE objvers = 'A'
          AND iobjnm = @name
          AND datefrom <= @key_date
          AND dateto >= @key_date
        ORDER BY hienm ASCENDING, version ASCENDING
        INTO TABLE @DATA(hierarchies).
      LOOP AT hierarchies INTO DATA(hierarchy).
        APPEND VALUE #( hienm   = hierarchy-hienm
                        version = hierarchy-version
                        slice   = zzxxmla1_cl_bw_auth=>read_slice( iobjnm   = name
                                                                    hienm    = hierarchy-hienm
                                                                    version  = hierarchy-version
                                                                    key_date = key_date ) )
          TO characteristic-hierarchies.
      ENDLOOP.
      APPEND characteristic TO list.
    ENDLOOP.
    result = create( region          = zzxxmla1_cl_bw_auth=>read( user     = user
                                                                  provider = provider
                                                                  key_date = key_date )
                     characteristics = list ).
  ENDMETHOD.

  METHOD create.
    result = NEW #( ).
    result->region = region.
    result->characteristics = characteristics.
    LOOP AT characteristics INTO DATA(characteristic).
      LOOP AT characteristic-hierarchies INTO DATA(hierarchy).
        APPEND result->view( iobjnm = characteristic-iobjnm hierarchy = hierarchy ) TO result->views.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD applying.
    result = region->applying( ).
  ENDMETHOD.

  METHOD values.
    TYPES ty_value TYPE c LENGTH 60.
    DATA keys TYPE STANDARD TABLE OF ty_value WITH EMPTY KEY.
    DATA(table) = |/BIC/S{ iobjnm }|.
    DATA(column) = |/BIC/{ iobjnm }|.
    SELECT (column)
      FROM (table)
      WHERE sid > 0
      ORDER BY (column)
      INTO TABLE @keys.
    LOOP AT keys INTO DATA(key) WHERE table_line IS NOT INITIAL.
      APPEND |{ key }| TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD label.
    result = condense( |{ hienm } { version }| ).
  ENDMETHOD.

  METHOD member_key.
    DATA node32 TYPE c LENGTH 32.
    IF iobjnm = characteristic.
      result = name.
    ELSE.
      node32 = name.
      CONCATENATE node32 iobjnm INTO result RESPECTING BLANKS.
      result = condense( result ).
    ENDIF.
  ENDMETHOD.

  METHOD view.
    result = VALUE #( iobjnm  = iobjnm
                      label   = label( hienm = hierarchy-hienm version = hierarchy-version )
                      hienm   = hierarchy-hienm
                      version = hierarchy-version
                      slice   = hierarchy-slice ).
    DATA(access) = region->hierarchy_access( iobjnm  = iobjnm
                                             hienm   = hierarchy-hienm
                                             version = hierarchy-version ).
    result-all = access-all.
    result-lines = access-lines.
    " a complete hierarchy (type 3) is shown as it is, its node of the values not assigned too
    result-restricted = xsdbool( access-all = abap_false AND access-lines = abap_true
                                 AND access-complete = abap_false ).
    LOOP AT hierarchy-slice-nodes INTO DATA(node).
      result-levels = nmax( val1 = result-levels val2 = node-level ).
    ENDLOOP.

    " the nodes in the order of the slice, each once (a link is shown where its node is)
    LOOP AT hierarchy-slice-nodes INTO node WHERE link = abap_false.
      IF line_exists( result-nodes[ iobjnm = node-iobjnm name = node-name ] ).
        CONTINUE.
      ENDIF.
      IF result-restricted = abap_false.
        DATA(parent) = VALUE zzxxmla1_cl_bw_auth=>ty_node(
                         hierarchy-slice-nodes[ nodeid = node-parentid ] OPTIONAL ).
        APPEND VALUE #( iobjnm        = node-iobjnm
                        name          = node-name
                        depth         = node-level - 1
                        expandable    = abap_true
                        top           = xsdbool( node-parentid = 0 )
                        parent_iobjnm = parent-iobjnm
                        parent_name   = parent-name ) TO result-nodes.
      ELSE.
        READ TABLE access-nodes INTO DATA(visible) WITH TABLE KEY iobjnm = node-iobjnm name = node-name.
        IF sy-subrc = 0.
          APPEND VALUE #( iobjnm        = visible-iobjnm
                          name          = visible-name
                          expandable    = visible-expandable
                          top           = visible-top
                          parent_iobjnm = COND #( WHEN visible-top = abap_false THEN visible-parent_iobjnm )
                          parent_name   = COND #( WHEN visible-top = abap_false THEN visible-parent_name ) )
            TO result-nodes.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " a restricted hierarchy is re-rooted: a node's level counts from its top node
    IF result-restricted = abap_true.
      LOOP AT result-nodes ASSIGNING FIELD-SYMBOL(<node>).
        DATA(above) = <node>.
        WHILE above-top = abap_false AND <node>-depth < 100.
          READ TABLE result-nodes INTO above WITH KEY iobjnm = above-parent_iobjnm name = above-parent_name.
          IF sy-subrc <> 0.
            EXIT.
          ENDIF.
          <node>-depth = <node>-depth + 1.
        ENDWHILE.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD slice_children.
    DATA(parents) = VALUE int4_table( FOR n IN slice-nodes WHERE ( iobjnm = iobjnm AND name = name ) ( n-nodeid ) ).
    LOOP AT slice-nodes INTO DATA(child) WHERE parentid <> 0.
      IF line_exists( parents[ table_line = child-parentid ] ).
        APPEND child TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD node_member.
    result = VALUE #( iobjnm      = view-iobjnm
                      kind        = zzxxmla1_cl_bw_auth=>c_kind-node
                      value       = name
                      hienm       = view-hienm
                      version     = view-version
                      node_iobjnm = iobjnm
                      named       = named ).
  ENDMETHOD.

  METHOD members_of_nodes.
    result = VALUE #( FOR n IN nodes ( node_member( view = view iobjnm = n-iobjnm name = n-name ) ) ).
  ENDMETHOD.

  METHOD keys_of_nodes.
    IF view-restricted = abap_true.
      result = VALUE #( FOR n IN nodes ( member_key( characteristic = view-iobjnm iobjnm = n-iobjnm name = n-name ) ) ).
    ENDIF.
  ENDMETHOD.

  METHOD hierarchy_members.
    result = members_of_nodes( view = view nodes = view-nodes ).
    IF view-restricted = abap_false.
      RETURN.
    ENDIF.
    LOOP AT view-nodes INTO DATA(node) WHERE expandable = abap_false.
      LOOP AT slice_children( slice = view-slice iobjnm = node-iobjnm name = node-name ) INTO DATA(child).
        APPEND node_member( view = view iobjnm = child-iobjnm name = child-name ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD flat_members.
    result = VALUE #( ( iobjnm = characteristic-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate ) ).
    LOOP AT characteristic-values INTO DATA(value).
      APPEND VALUE #( iobjnm = characteristic-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value value = value )
        TO result.
    ENDLOOP.
    " and the value not assigned (# or 000), which BW shows last
    APPEND VALUE #( iobjnm = characteristic-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value ) TO result.
  ENDMETHOD.

  METHOD row_sets.
    APPEND VALUE #( label = |[{ characteristic-iobjnm }]| members = flat_members( characteristic ) flat = abap_true )
      TO result.
    LOOP AT views INTO DATA(view) WHERE iobjnm = characteristic-iobjnm.
      APPEND VALUE #( label      = view-label
                      members    = hierarchy_members( view )
                      restricted = view-restricted
                      shown      = keys_of_nodes( view = view nodes = view-nodes ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD tuples.
    LOOP AT first INTO DATA(member).
      IF second IS SUPPLIED.
        LOOP AT second INTO DATA(other).
          APPEND VALUE #( BASE with ( member ) ( other ) ) TO result.
        ENDLOOP.
      ELSE.
        APPEND VALUE #( BASE with ( member ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD answered.
    result = row.
    DATA(check) = COND #( WHEN selection IS INITIAL THEN region->check_members( named )
                          ELSE region->check( selection ) ).
    result-status = check-status.
    result-reason = check-reason.
    result-message = check-message.
    IF selection IS INITIAL AND check-status = zzxxmla1_cl_bw_auth=>c_status-allowed.
      result-status = c_empty.
    ENDIF.
    IF result-status <> zzxxmla1_cl_bw_auth=>c_status-allowed.
      CLEAR: result-restricted, result-members.
    ENDIF.
  ENDMETHOD.

  METHOD run.
    " the hierarchies BW lists to the user: those with a line of the user, all of a characteristic with *
    LOOP AT characteristics INTO DATA(characteristic).
      DATA(listed) = VALUE string_table( FOR v IN views WHERE ( iobjnm = characteristic-iobjnm
                                                                AND ( all = abap_true OR lines = abap_true ) )
                                         ( v-label ) ).
      APPEND VALUE #( characteristic = characteristic-iobjnm
                      test           = `HIERARCHIES`
                      status         = zzxxmla1_cl_bw_auth=>c_status-allowed
                      answer         = concat_lines_of( table = listed sep = `; ` ) ) TO result.
    ENDLOOP.

    APPEND answered( row = VALUE #( test = `TOTAL` ) selection = VALUE #( ( VALUE #( ) ) ) ) TO result.
    LOOP AT characteristics INTO characteristic.
      APPEND LINES OF flat_queries( characteristic ) TO result.
      LOOP AT views INTO DATA(view) WHERE iobjnm = characteristic-iobjnm.
        APPEND LINES OF hierarchy_queries( view ) TO result.
      ENDLOOP.
    ENDLOOP.
    LOOP AT characteristics INTO DATA(rows_of).
      LOOP AT characteristics INTO DATA(filter_of) WHERE iobjnm <> rows_of-iobjnm.
        APPEND LINES OF combined_queries( rows_of = rows_of filter_of = filter_of ) TO result.
      ENDLOOP.
    ENDLOOP.

    IF lines( characteristics ) < 2.
      RETURN.
    ENDIF.
    DATA(first) = characteristics[ 1 ].
    DATA(second) = characteristics[ 2 ].
    LOOP AT pairs INTO DATA(pair).
      DATA(slicer) = VALUE zzxxmla1_cl_bw_auth=>ty_tuple(
        ( iobjnm = first-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value value = pair-first named = abap_true )
        ( iobjnm = second-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value value = pair-second named = abap_true ) ).
      APPEND answered( row       = VALUE #( characteristic = first-iobjnm
                                            hierarchy      = |[{ first-iobjnm }]|
                                            test           = `PAIR`
                                            node           = pair-first
                                            filter_char    = second-iobjnm
                                            filter_node    = pair-second )
                       selection = VALUE #( ( slicer ) ) ) TO result.
    ENDLOOP.
    " a crossjoin is the same both ways round: each characteristic with each later one
    LOOP AT characteristics INTO DATA(left).
      DATA(following) = sy-tabix + 1.
      LOOP AT characteristics INTO DATA(right) FROM following.
        APPEND LINES OF crossjoin_queries( rows_of = left cross_with = right ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD flat_queries.
    DATA(row) = VALUE ty_result( characteristic = characteristic-iobjnm hierarchy = |[{ characteristic-iobjnm }]| ).
    DATA(members) = flat_members( characteristic ).
    row-test = `MEMBERS`.
    APPEND answered( row = row selection = tuples( members ) ) TO result.
    row-test = `MEMBERS NE`.
    APPEND answered( row = row selection = tuples( members ) ) TO result.

    " LEVEL00 the All member, LEVEL01 the values
    row-test = `LEVEL`.
    row-node = `LEVEL00`.
    APPEND answered( row = row selection = tuples( VALUE #( ( members[ 1 ] ) ) ) ) TO result.
    DELETE members INDEX 1.
    row-node = `LEVEL01`.
    APPEND answered( row = row selection = tuples( members ) ) TO result.

    row-test = `SLICER`.
    LOOP AT characteristic-values INTO DATA(value).
      row-node = value.
      APPEND answered( row       = row
                       selection = VALUE #( ( VALUE #( ( iobjnm = characteristic-iobjnm
                                                         kind   = zzxxmla1_cl_bw_auth=>c_kind-value
                                                         value  = value
                                                         named  = abap_true ) ) ) ) ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD hierarchy_queries.
    DATA seen TYPE ty_view_node.
    DATA(row) = VALUE ty_result( characteristic = view-iobjnm hierarchy = view-label ).
    DATA(members) = hierarchy_members( view ).
    row-restricted = view-restricted.
    row-members = keys_of_nodes( view = view nodes = view-nodes ).
    row-test = `MEMBERS`.
    APPEND answered( row = row selection = tuples( members ) ) TO result.
    row-test = `MEMBERS NE`.
    APPEND answered( row = row selection = tuples( members ) ) TO result.

    " a level shows the visible nodes of its depth; of a hierarchy without a line of the user none
    row-test = `LEVEL`.
    DO view-levels TIMES.
      DATA(depth) = sy-index - 1.
      DATA(level_nodes) = COND ty_view_nodes( WHEN view-all = abap_true OR view-lines = abap_true
                                              THEN VALUE #( FOR n IN view-nodes WHERE ( depth = depth ) ( n ) ) ).
      row-node = |LEVEL{ depth WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
      row-members = keys_of_nodes( view = view nodes = level_nodes ).
      APPEND answered( row = row selection = tuples( members_of_nodes( view = view nodes = level_nodes ) ) )
        TO result.
    ENDDO.

    " per node of the slice: as slicer, on the rows, its children and its parent
    LOOP AT view-slice-nodes INTO DATA(node).
      DATA(member) = node_member( view = view iobjnm = node-iobjnm name = node-name named = abap_true ).
      DATA(named) = VALUE zzxxmla1_cl_bw_auth=>ty_tuple( ( member ) ).
      row = VALUE #( characteristic = view-iobjnm hierarchy = view-label node = node-name ).
      row-test = `SLICER`.
      APPEND answered( row = row selection = VALUE #( ( named ) ) ) TO result.
      row-test = `ROWS`.
      APPEND answered( row = row selection = VALUE #( ( named ) ) ) TO result.

      CLEAR seen.
      READ TABLE view-nodes INTO seen WITH KEY iobjnm = node-iobjnm name = node-name.
      DATA(visible) = xsdbool( sy-subrc = 0 ).
      IF node-iobjnm <> view-iobjnm.
        DATA(children) = COND ty_view_nodes( WHEN visible = abap_true AND seen-expandable = abap_true
                                             THEN VALUE #( FOR n IN view-nodes WHERE ( top = abap_false
                                                                                 AND parent_iobjnm = node-iobjnm
                                                                                 AND parent_name = node-name )
                                                           ( n ) ) ).
        row-restricted = view-restricted.
        row-members = keys_of_nodes( view = view nodes = children ).
        DATA(selection) = tuples( first = members_of_nodes( view = view nodes = children ) with = named ).
        row-test = `CHILDREN`.
        APPEND answered( row = row selection = selection named = named ) TO result.
        row-test = `CHILDREN NE`.
        APPEND answered( row = row selection = selection named = named ) TO result.
      ENDIF.
      IF node-parentid <> 0.
        DATA(parents) = COND ty_view_nodes( WHEN visible = abap_true AND seen-top = abap_false
                                            THEN VALUE #( FOR n IN view-nodes WHERE ( iobjnm = seen-parent_iobjnm
                                                                                AND name = seen-parent_name )
                                                          ( n ) ) ).
        row-restricted = view-restricted.
        row-members = keys_of_nodes( view = view nodes = parents ).
        row-test = `PARENT`.
        APPEND answered( row       = row
                         selection = tuples( first = members_of_nodes( view = view nodes = parents ) with = named )
                         named     = named ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD combined_queries.
    " the restrictions on the other characteristic: its values, the text nodes of its hierarchies
    TYPES: BEGIN OF ty_filter,
             hierarchy TYPE string,
             node      TYPE string,
             member    TYPE zzxxmla1_cl_bw_auth=>ty_member,
           END OF ty_filter.
    DATA filters TYPE STANDARD TABLE OF ty_filter WITH EMPTY KEY.
    LOOP AT filter_of-values INTO DATA(value).
      APPEND VALUE #( hierarchy = |[{ filter_of-iobjnm }]|
                      node      = value
                      member    = VALUE #( iobjnm = filter_of-iobjnm kind = zzxxmla1_cl_bw_auth=>c_kind-value
                                           value = value named = abap_true ) ) TO filters.
    ENDLOOP.
    LOOP AT views INTO DATA(view) WHERE iobjnm = filter_of-iobjnm.
      LOOP AT view-slice-nodes INTO DATA(node) WHERE iobjnm <> filter_of-iobjnm.
        APPEND VALUE #( hierarchy = view-label
                        node      = node-name
                        member    = node_member( view = view iobjnm = node-iobjnm name = node-name
                                                 named = abap_true ) ) TO filters.
      ENDLOOP.
    ENDLOOP.

    LOOP AT row_sets( rows_of ) INTO DATA(row_set).
      LOOP AT filters INTO DATA(filter).
        APPEND answered( row       = VALUE #( characteristic   = rows_of-iobjnm
                                              hierarchy        = row_set-label
                                              test             = `COMBINED`
                                              filter_char      = filter_of-iobjnm
                                              filter_hierarchy = filter-hierarchy
                                              filter_node      = filter-node
                                              restricted       = row_set-restricted
                                              members          = row_set-shown )
                         selection = tuples( first = row_set-members with = VALUE #( ( filter-member ) ) ) )
          TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD crossjoin_queries.
    DATA(left_sets) = row_sets( rows_of ).
    DATA(right_sets) = row_sets( cross_with ).
    LOOP AT left_sets INTO DATA(left).
      LOOP AT right_sets INTO DATA(right).
        " one side flat
        IF left-flat = abap_false AND right-flat = abap_false.
          CONTINUE.
        ENDIF.
        DATA(row) = VALUE ty_result( characteristic   = rows_of-iobjnm
                                     hierarchy        = left-label
                                     filter_char      = cross_with-iobjnm
                                     filter_hierarchy = right-label ).
        DATA(selection) = tuples( first = left-members second = right-members ).
        row-test = `CROSSJOIN`.
        APPEND answered( row = row selection = selection ) TO result.
        row-test = `CROSSJOIN NE`.
        APPEND answered( row = row selection = selection ) TO result.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
