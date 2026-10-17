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
"! The copies of BW's time-independent hierarchies that the engine reads (docs/next-steps.md, Now: time-independent BW
"! hierarchies, part one): per InfoObject a node table, a closure table and a view of the closure with the
"! not-assigned values, holding all of its hierarchies, as BW's SID structure /BIC/I of the characteristic does, and
"! per copy a row of the directory ZZXXMLA1_HIEDIR (keyed by HIEID, HIESID and SVER).
"! - Node table (ZZXXMLA1H followed by 7 digits): a row per occurrence, the shared subtrees expanded as BW's SID
"!   structure /BIC/I holds them, keyed by HIESID, SVER, PARENT_SID and SID. An inner node has its own negative node SID of
"!   /BIC/K (also each occurrence inside an expanded link, the postable nodes and the virtual root ROOTSID of
"!   RSRHIEDIR_OLAP, the All member, PARENT_SID 0, DEPTH 0, POS 0), a leaf the characteristic's SID (a leaf occurrence
"!   is PARENT_SID and SID). DEPTH is BW's TLEVEL, POS the depth-first number (BW's LISTNO; the values of an interval,
"!   which share its LISTNO, by SID), END_POS the last POS of the subtree. NODE_IOBJ and NODE_NAME are BW's node name
"!   (0HIER_NODE and the text node's name, or the characteristic and the key of a postable node, whose own value
"!   VALUE_SID is its first leaf); a leaf is named by the characteristic's view.
"! - Closure table (ZZXXMLA1C, the same digits): per inner node occurrence the distinct SIDs of the leaves below it,
"!   and per leaf its identity row (ANCESTOR_SID = SID), keyed by HIESID, SVER, ANCESTOR_SID and SID, so that every
"!   member, node or leaf, is an ancestor, a fact read is one join (facts to the closure on SID, grouped by
"!   ANCESTOR_SID) and a value reached by two paths counts once. Leaf SIDs are positive, node SIDs negative. The table
"!   holds the assigned values only, whether the hierarchy shows the not-assigned node or not.
"! - Not-assigned view (database view ZZXXMLA1R, DDL source ZZXXMLA1_R, the same digits): the table's rows and, for
"!   every copy of the directory whose hierarchy shows the not-assigned node (BW's setting RSHIEDIR-NORESTNODES, the UI
"!   offers no switch), three rows per SID of the SID table under no leaf: the not-assigned node REST_H
"!   (REST_TOP_SID) to it, the All member (ROOT_SID) to it and its identity row. These SIDs are an anti-join, the SID
"!   table left-outer-joined to the All member's rows; the hierarchies come from the directory, so the view has no
"!   parameters, follows a new copy once the directory names it and follows master data loads without a refill. A
"!   query reads the view for a hierarchy that shows the not-assigned node, else the table (ty_hierarchy-closure).
"! - A copy is keyed by BW's HIESID and SVER (RSRHIEDIR_OLAP), so that it compares with /BIC/I row by row: BW does
"!   not change a structure once its SVER is written, a change is a new SVER (up to 33 per hierarchy, then given
"!   again). BW keeps an old SVER (its row with DELETETIMESTMP set) until no query needs it; the copy of every HIESID and
"!   SVER with a row in RSRHIEDIR_OLAP of the same TIMESTMP is kept, the others are deleted by the next refill of the
"!   hierarchy (a copy of BW's current HIESID and SVER but another TIMESTMP is of an earlier use of that SVER). A
"!   refill writes the new copy next to the old ones and commits it with its directory row, so a query that read a
"!   directory row keeps its rows (HANA's read consistency is per statement, not per query).
"! The tables and the view are DDIC objects in $TMP (as the generated views; ADBC's tables need HANA's enterprise
"! license and are hard to transport), client-independent as BW's, created by create_tables when a schema that names a
"! hierarchy of the InfoObject is accepted, never by a query. A query calls current: one key read each of the directory
"! and RSRHIEDIR_OLAP; when there is no copy of BW's current row (HIESID, SVER, TIMESTMP), it is refilled under the
"! lock ENQUEUE_E_TABLE on ZZXXMLA1_HIEDIR, which another query of the hierarchy waits for. The refill stays in the
"! database (INSERT ... SELECT from /BIC/I and /BIC/K) and refuses, as a fault of the query
"! (ZZXXMLA1_CX_BW_HIERARCHY): a value both an inner node and a leaf, a value twice as an inner node with different
"! subtrees, more than one current row of RSRHIEDIR_OLAP, a time- or version-dependent hierarchy; and a copy whose
"! distinct values per node differ from BW's (its leaf rows plus the correction rows, LISTNO 0, of it and the inner
"! nodes below it, with their factors).
"! No limit on occurrences: shared subtrees are expanded whatever their size.
CLASS zzxxmla1_cl_bw_hierarchy_copy DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    "! The package of the generated tables unless the caller names another: local, as the generated views.
    CONSTANTS c_default_package TYPE devclass VALUE '$TMP'.
    CONSTANTS c_node_prefix TYPE string VALUE `ZZXXMLA1H`.
    CONSTANTS c_closure_prefix TYPE string VALUE `ZZXXMLA1C`.
    "! The not-assigned view: its database view and its DDL source.
    CONSTANTS c_rest_view_prefix TYPE string VALUE `ZZXXMLA1R`.
    CONSTANTS c_rest_ddl_prefix TYPE string VALUE `ZZXXMLA1_R`.
    "! The node name of BW's text nodes and of the not-assigned node (/BIC/K-NIOBJNM).
    CONSTANTS c_text_node TYPE rsniobjnm VALUE '0HIER_NODE'.
    "! The name of the not-assigned node (BW's node name of REST_TOP_SID).
    CONSTANTS c_rest_node_name TYPE string VALUE `REST_H`.
    "! The parts of a level's columns of levels_sql.
    CONSTANTS:
      BEGIN OF c_level_part,
        sid     TYPE string VALUE `SID`,
        name    TYPE string VALUE `NAME`,
        pos     TYPE string VALUE `POS`,
        caption TYPE string VALUE `CAPTION`,
      END OF c_level_part.

    TYPES:
      "! the generated objects of an InfoObject
      BEGIN OF ty_tables,
        node      TYPE tabname,
        closure   TYPE tabname,
        rest_view TYPE tabname,
        rest_ddl  TYPE ddlname,
      END OF ty_tables.
    TYPES:
      "! a hierarchy's current copy, as a query reads it: its tables, the closure a query reads (the not-assigned view
      "! when the hierarchy shows that node, else the closure table), BW's HIESID and SVER it is a copy of (to bind
      "! in each statement), the SIDs of its All member and of its not-assigned node, and whether it shows that node
      BEGIN OF ty_hierarchy,
        hieid          TYPE rshieid,
        characteristic TYPE rsiobjnm,
        name           TYPE rshienm,
        node_table     TYPE tabname,
        closure_table  TYPE tabname,
        closure        TYPE tabname,
        hiesid         TYPE i,
        sver           TYPE rsrsver,
        root_sid       TYPE i,
        rest_top_sid   TYPE i,
        rest_shown     TYPE abap_bool,
        refilled       TYPE abap_bool,
      END OF ty_hierarchy.
    TYPES:
      "! a statement and the values of its parameters
      BEGIN OF ty_statement,
        sql    TYPE string,
        params TYPE zzxxmla1_cl_sql=>ty_t_param,
      END OF ty_statement.

    TYPES ty_r_iobjnm TYPE RANGE OF rsiobjnm.
    TYPES ty_r_hienm TYPE RANGE OF rshienm.
    TYPES:
      "! the outcome of copying a hierarchy (run): the copy, or the error; its counts and the time of current
      BEGIN OF ty_run,
        characteristic TYPE rsiobjnm,
        name           TYPE rshienm,
        error          TYPE string,
        tables         TYPE ty_tables,
        hierarchy      TYPE ty_hierarchy,
        nodes          TYPE i,          " node rows
        inner_nodes    TYPE i,
        closure_rows   TYPE i,          " of the closure table
        depth          TYPE i,
        identity_rows  TYPE i,
        root_rows      TYPE i,          " the All member's rows of the closure table
        all_values     TYPE i,          " the All member's values, read as a query reads them
        rest_values    TYPE i,          " the not-assigned node's values, read as a query reads them
        microseconds   TYPE i,
      END OF ty_run,
      ty_t_run TYPE STANDARD TABLE OF ty_run WITH EMPTY KEY.
    TYPES:
      "! a hierarchy BW has for a characteristic (offered): its name, its text, and whether olap4abap can serve it,
      "! else why not
      BEGIN OF ty_offered,
        name      TYPE string,
        text      TYPE string,
        supported TYPE abap_bool,
        reason    TYPE string,
      END OF ty_offered,
      ty_t_offered TYPE STANDARD TABLE OF ty_offered WITH EMPTY KEY.

    "! package: the package new tables are created in.
    METHODS constructor
      IMPORTING package TYPE devclass DEFAULT c_default_package.
    "! Creates the node and closure tables and the not-assigned view of an InfoObject if it has none (accept of a
    "! schema that names one of its hierarchies); an InfoObject that has them keeps them.
    METHODS create_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! Deletes the not-assigned view, the node and closure tables and the copies of an InfoObject, if it has them:
    "! the view reads BW's SID table, so BW cannot delete the InfoObject while it exists (the clinic demo's run).
    METHODS delete_tables
      IMPORTING characteristic TYPE rsiobjnm.
    "! The current copy of a hierarchy of a characteristic (the basic one, RSHIEDIR-IOBJNM), refilled first if BW's
    "! is newer. Raises ZZXXMLA1_CX_BW_HIERARCHY.
    METHODS current
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
      RETURNING VALUE(result)  TYPE ty_hierarchy.
    "! The statement of the SIDs below a member of the copy, node or leaf, one column SID: its rows of the closure the
    "! hierarchy is read from (the not-assigned node's and the All member's with the values under no leaf when the
    "! hierarchy shows the not-assigned node).
    CLASS-METHODS values_of
      IMPORTING hierarchy     TYPE ty_hierarchy
                node_sid      TYPE i
      RETURNING VALUE(result) TYPE ty_statement.
    "! The number of levels of a copy, below its All member: the depth of its deepest node row (BW's TLEVEL, the roots
    "! 1), at least 2 when the hierarchy shows the not-assigned node (REST_H a root, its values one level below it).
    "! The schema makes the levels Level 01 to Level nn of it (ZZXXMLA1_CL_SCHEMA).
    CLASS-METHODS depth
      IMPORTING hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE i.
    "! The number of members on a level of a copy (1: the roots): its node rows of that depth, every occurrence; when
    "! the hierarchy shows the not-assigned node, REST_H on level 1 and its values on level 2 as well.
    CLASS-METHODS level_cardinality
      IMPORTING hierarchy     TYPE ty_hierarchy
                !level        TYPE i
      RETURNING VALUE(result) TYPE i.
    "! The levels (1: the roots) on which a SID occurs more than once: a value that is a leaf under two parents, so
    "! that its key alone does not tell the member (the level's uniqueMembers false). An inner node has an own SID per
    "! occurrence, the not-assigned values are under no leaf.
    CLASS-METHODS repeated_levels
      IMPORTING hierarchy     TYPE ty_hierarchy
      RETURNING VALUE(result) TYPE int4_table.
    "! The column of a level of levels_sql: L01_SID, L01_NAME, L01_POS, L01_CAPTION, ...
    "! @parameter part | c_level_part
    CLASS-METHODS level_column
      IMPORTING !level        TYPE i
                part          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The members of a copy as a level hierarchy (ZZXXMLA1_CL_MODEL=>member_table of a BW hierarchy), a query to use
    "! as a derived table: a row per member, every occurrence of a node or a leaf (a leaf under two parents twice),
    "! with per level of its path, from the roots down to its own, the member there (level_column): its SID, its name,
    "! its position (POS, BW's order) and, with a caption column, its caption, the levels below it NULL; as the
    "! reference's flattened table of a level hierarchy, but a member on the level of its depth whether it has children
    "! or not (SSAS's parent-child form). A node is named and captioned by its node name (NODE_NAME, the key of a
    "! postable node), a leaf named and captioned as the characteristic's member is, by the view's columns (the
    "! initial value too: '' by KEY_NAME). When the hierarchy shows the not-assigned node, REST_H follows the roots, its
    "! values (the closure's rows under it) below it in their names' order. The levels of a member are read up its
    "! parents, one join each (an inner node's SID is its occurrence's), so depth is the number of levels.
    "! @parameter value_table | the characteristic's table that names the leaves (the dimension's view)
    "! @parameter sid_column | its SID column
    "! @parameter name_column | its column of the value's name (the level's nameColumn over the key attribute)
    "! @parameter caption_column | its column of the value's caption (the key attribute's NameColumn), if any
    CLASS-METHODS levels_sql
      IMPORTING hierarchy      TYPE ty_hierarchy
                depth          TYPE i
                value_table    TYPE string
                sid_column     TYPE string
                name_column    TYPE string
                caption_column TYPE string OPTIONAL
      RETURNING VALUE(result)  TYPE string.
    "! Creates the objects of each characteristic and copies each of its time-independent hierarchies that are not
    "! version dependent (program ZZXXMLA1_HIERARCHY_COPY, the class run for scripts/hierarchy_copy_test.py).
    METHODS run
      IMPORTING characteristics TYPE ty_r_iobjnm
                hierarchies     TYPE ty_r_hienm OPTIONAL
      RETURNING VALUE(result)   TYPE ty_t_run.
    "! The active hierarchies BW has for a characteristic (the basic one, RSHIEDIR-IOBJNM), by name, which the schema
    "! builder offers: each with its text in the logon language (medium, else long, else short, else the name), served
    "! if it is neither time nor version dependent (one row of RSHIEDIR, as current asks).
    CLASS-METHODS offered
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_t_offered.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      "! the tables of BW a refill reads
      BEGIN OF ty_bw_tables,
        structure TYPE tabname,   " /BIC/I: SID structure
        node_sids TYPE tabname,   " /BIC/K: node SIDs and names
        sids      TYPE tabname,   " /BIC/S: the characteristic's SIDs
      END OF ty_bw_tables.
    TYPES:
      "! BW's current state of a hierarchy, which a copy is compared with
      BEGIN OF ty_bw_state,
        hieid        TYPE rshieid,
        iobjnm       TYPE rsiobjnm,
        hienm        TYPE rshienm,
        norestnodes  TYPE rshiernorest,
        hiesid       TYPE i,
        sver         TYPE rsrsver,
        timestmp     TYPE rstimestmp,
        root_sid     TYPE i,
        rest_top_sid TYPE i,
      END OF ty_bw_state.
    TYPES ty_directory TYPE zzxxmla1_hiedir.
    TYPES ty_t_directory TYPE STANDARD TABLE OF zzxxmla1_hiedir WITH EMPTY KEY.
    TYPES:
      "! a version of a hierarchy BW keeps: a row of RSRHIEDIR_OLAP, current or old
      BEGIN OF ty_version,
        hiesid   TYPE i,
        sver     TYPE rsrsver,
        timestmp TYPE rstimestmp,
      END OF ty_version,
      ty_t_version TYPE STANDARD TABLE OF ty_version WITH EMPTY KEY.
    TYPES:
      "! a column of a generated table: name, data element, key
      BEGIN OF ty_column,
        name     TYPE fieldname,
        rollname TYPE rollname,
        key      TYPE abap_bool,
      END OF ty_column,
      ty_t_column TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.
    "! A refill waits for another one this many times, each the enqueue server's wait (ENQUEUE_E_TABLE, _wait).
    CONSTANTS c_lock_attempts TYPE i VALUE 60.
    "! /BIC/I-LISTNO of the not-assigned rows: from here on.
    CONSTANTS c_rest_listno TYPE i VALUE 999999998.

    DATA package TYPE devclass.
    DATA handler TYPE REF TO if_dd_ddl_handler.

    "! BW's current state of a hierarchy: its row of RSHIEDIR (time-independent, not version dependent) and its
    "! current row of RSRHIEDIR_OLAP (DELETETIMESTMP 0, which must be one).
    METHODS bw_state
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
      RETURNING VALUE(result)  TYPE ty_bw_state.
    METHODS bw_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_bw_tables.
    "! The objects of the registry ZZXXMLA1_HIETAB; initial if the InfoObject has none.
    METHODS registered_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! Whether the node and closure tables and the not-assigned view are active in the DDIC.
    METHODS tables_exist
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE abap_bool.
    "! Whether the directory row is a copy of BW's current state.
    CLASS-METHODS up_to_date
      IMPORTING directory     TYPE ty_directory
                bw            TYPE ty_bw_state
      RETURNING VALUE(result) TYPE abap_bool.
    "! The copies of a hierarchy that BW keeps no version of (its HIESID, SVER and TIMESTMP).
    CLASS-METHODS stale_copies
      IMPORTING copies        TYPE ty_t_directory
                versions      TYPE ty_t_version
      RETURNING VALUE(result) TYPE ty_t_directory.
    "! The hierarchy as a query reads it from its directory row.
    CLASS-METHODS hierarchy_of
      IMPORTING directory     TYPE ty_directory
                tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE ty_hierarchy.
    METHODS lock
      IMPORTING hieid TYPE rshieid.
    METHODS unlock
      IMPORTING hieid TYPE rshieid.
    "! Deletes the copies BW keeps no version of, writes the copy of BW's current SVER, checks it, commits it with its
    "! directory row; a refusal rolls back.
    METHODS refill
      IMPORTING bw            TYPE ty_bw_state
                tables        TYPE ty_tables
                bw_tables     TYPE ty_bw_tables
      RETURNING VALUE(result) TYPE ty_directory.
    "! Deletes the rows of a copy, of one HIESID and SVER.
    METHODS delete_copy
      IMPORTING tables TYPE ty_tables
                hiesid TYPE i
                sver   TYPE rsrsver.
    "! The checks of a new copy: a refusal or a difference from BW raises ZZXXMLA1_CX_BW_HIERARCHY.
    METHODS check
      IMPORTING bw        TYPE ty_bw_state
                tables    TYPE ty_tables
                bw_tables TYPE ty_bw_tables.
    "! Whether the generated tables have the columns of node_columns and closure_columns, in their order.
    METHODS current_columns
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS delete_table
      IMPORTING name TYPE tabname.
    "! The statements of a refill (the parameters in the order of their ?; HIESID and SVER are a copy's key).
    "! nodes: HIESID, SVER, ROOTSID
    CLASS-METHODS nodes_sql
      IMPORTING tables        TYPE ty_tables
                bw_tables     TYPE ty_bw_tables
      RETURNING VALUE(result) TYPE string.
    "! subtree ends of the inner nodes: HIESID, SVER
    CLASS-METHODS end_pos_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! closure, the inner nodes' rows and the leaves' identity rows: HIESID, SVER, HIESID, SVER
    CLASS-METHODS closure_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! values both an inner node and a leaf elsewhere, SID and node name: characteristic, HIESID, SVER,
    "! characteristic
    CLASS-METHODS node_and_leaf_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! values twice an inner node with different subtrees, SID and node name: HIESID, SVER, characteristic
    CLASS-METHODS different_subtrees_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! nodes whose distinct values differ from BW's, SID, name, ours and BW's: HIESID, SVER, HIESID, SVER
    CLASS-METHODS differences_sql
      IMPORTING tables        TYPE ty_tables
                bw_tables     TYPE ty_bw_tables
      RETURNING VALUE(result) TYPE string.
    "! the columns of the node and closure tables
    CLASS-METHODS node_columns
      RETURNING VALUE(result) TYPE ty_t_column.
    CLASS-METHODS closure_columns
      RETURNING VALUE(result) TYPE ty_t_column.
    METHODS create_table
      IMPORTING name        TYPE tabname
                description TYPE as4text
                columns     TYPE ty_t_column.
    "! Creates (or writes again) the not-assigned view and activates it.
    METHODS create_rest_view
      IMPORTING characteristic TYPE rsiobjnm
                tables         TYPE ty_tables.
    "! Deletes the not-assigned view if it exists.
    METHODS delete_rest_view
      IMPORTING tables TYPE ty_tables.
    "! The DDL source of the not-assigned view of an InfoObject whose SID table is sid_table.
    CLASS-METHODS rest_view_source
      IMPORTING characteristic TYPE rsiobjnm
                tables         TYPE ty_tables
                sid_table      TYPE tabname
      RETURNING VALUE(result)  TYPE string.
    "! The description of the not-assigned view.
    CLASS-METHODS rest_view_description
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ddtext.
    METHODS ddl_handler
      RETURNING VALUE(result) TYPE REF TO if_dd_ddl_handler.
    "! the next number after the highest one of a generated node or closure table
    METHODS next_table_number
      RETURNING VALUE(result) TYPE i.
    "! the generated objects of a number
    CLASS-METHODS tables_of_number
      IMPORTING number        TYPE i
      RETURNING VALUE(result) TYPE ty_tables.
    CLASS-METHODS table_name
      IMPORTING prefix        TYPE string
                number        TYPE i
      RETURNING VALUE(result) TYPE tabname.
    CLASS-METHODS quote
      IMPORTING identifier    TYPE csequence
      RETURNING VALUE(result) TYPE string.
    CLASS-METHODS refuse
      IMPORTING text TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_bw_hierarchy_copy IMPLEMENTATION.

  METHOD constructor.
    me->package = package.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    " the plain hierarchies of the clinic demo, tab-separated for scripts/hierarchy_copy_test.py
    DATA(rows) = run( VALUE #( sign = 'I' option = 'EQ' ( low = 'ZCLDIAG' ) ( low = 'ZCLPAT' ) ( low = 'ZCLSERV' ) ) ).
    DATA(t) = cl_abap_char_utilities=>horizontal_tab.
    LOOP AT rows INTO DATA(row).
      IF row-error IS NOT INITIAL.
        out->write( |{ row-characteristic }{ t }{ row-name }{ t }ERROR{ t }{ row-error }| ).
        CONTINUE.
      ENDIF.
      DATA(hierarchy) = row-hierarchy.
      out->write( |{ row-characteristic }{ t }{ row-name }{ t }OK{ t }{ row-tables-node }{ t }{ row-tables-closure }{ t }| &&
                  |{ hierarchy-hiesid }/{ hierarchy-sver }{ t }{ hierarchy-refilled }{ t }{ hierarchy-root_sid }{ t }| &&
                  |{ hierarchy-rest_top_sid }{ t }{ hierarchy-rest_shown }{ t }{ row-nodes }{ t }{ row-inner_nodes }{ t }| &&
                  |{ row-closure_rows }{ t }{ row-depth }{ t }{ row-all_values }{ t }{ row-rest_values }{ t }| &&
                  |{ row-microseconds }{ t }{ row-identity_rows }{ t }{ row-root_rows }{ t }{ hierarchy-closure }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run.
    SELECT iobjnm, hienm FROM rshiedir
      WHERE iobjnm IN @characteristics AND hienm IN @hierarchies AND objvers = 'A' AND version = ''
        AND dateto = '99991231'
      ORDER BY iobjnm ASCENDING, hienm ASCENDING
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      DATA(line) = VALUE ty_run( characteristic = row-iobjnm name = row-hienm ).
      TRY.
          line-tables = create_tables( row-iobjnm ).
          GET RUN TIME FIELD DATA(started).
          line-hierarchy = current( characteristic = row-iobjnm name = row-hienm ).
          GET RUN TIME FIELD DATA(stopped).
          line-microseconds = stopped - started.
          DATA(hiesid) = NEW i( line-hierarchy-hiesid ).
          DATA(sver) = NEW string( line-hierarchy-sver ).
          DATA(root_sid) = NEW i( line-hierarchy-root_sid ).
          DATA(node) = quote( line-tables-node ).
          DATA(closure) = quote( line-tables-closure ).
          DATA(counts) = zzxxmla1_cl_sql=>query(
            sql     = |SELECT ( SELECT COUNT( * ) FROM { node } WHERE "HIESID" = ? AND "SVER" = ? ), | &&
                      |( SELECT COUNT( * ) FROM { node } WHERE "HIESID" = ? AND "SVER" = ? AND "SID" < 0 ), | &&
                      |( SELECT COUNT( * ) FROM { closure } WHERE "HIESID" = ? AND "SVER" = ? ), | &&
                      |( SELECT MAX( "DEPTH" ) FROM { node } WHERE "HIESID" = ? AND "SVER" = ? ), | &&
                      |( SELECT COUNT( * ) FROM { closure } WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = "SID" ), | &&
                      |( SELECT COUNT( * ) FROM { closure } WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ? ) | &&
                      |FROM DUMMY|
            columns = 6
            params  = VALUE #( ( hiesid ) ( sver ) ( hiesid ) ( sver ) ( hiesid ) ( sver ) ( hiesid ) ( sver )
                               ( hiesid ) ( sver ) ( hiesid ) ( sver ) ( root_sid ) ) ).
          DATA(count) = counts[ 1 ].
          line-nodes = count[ 1 ].
          line-inner_nodes = count[ 2 ].
          line-closure_rows = count[ 3 ].
          line-depth = count[ 4 ].
          line-identity_rows = count[ 5 ].
          line-root_rows = count[ 6 ].
          DATA(root) = values_of( hierarchy = line-hierarchy node_sid = line-hierarchy-root_sid ).
          DATA(rest) = values_of( hierarchy = line-hierarchy node_sid = line-hierarchy-rest_top_sid ).
          line-all_values = lines( zzxxmla1_cl_sql=>query( sql = root-sql columns = 1 params = root-params ) ).
          line-rest_values = lines( zzxxmla1_cl_sql=>query( sql = rest-sql columns = 1 params = rest-params ) ).
        CATCH zzxxmla1_cx_bw_hierarchy zzxxmla1_cx_sql INTO DATA(error).
          line-error = error->get_text( ).
      ENDTRY.
      APPEND line TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD offered.
    SELECT d~hienm, d~version, d~dateto, t~txtsh, t~txtmd, t~txtlg
      FROM rshiedir AS d
      LEFT OUTER JOIN rshiedirt AS t ON t~hieid = d~hieid AND t~objvers = d~objvers AND t~langu = @sy-langu
      WHERE d~iobjnm = @characteristic AND d~objvers = 'A'
      ORDER BY d~hienm ASCENDING, d~dateto DESCENDING, d~version ASCENDING
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row) GROUP BY row-hienm INTO DATA(group).
      DATA(entry) = VALUE ty_offered( name = condense( group ) supported = abap_true ).
      DATA(count) = 0.
      LOOP AT GROUP group INTO DATA(member).
        count = count + 1.
        IF entry-text IS INITIAL.
          entry-text = condense( COND string( WHEN member-txtmd IS NOT INITIAL THEN member-txtmd
                                              WHEN member-txtlg IS NOT INITIAL THEN member-txtlg
                                              ELSE member-txtsh ) ).
        ENDIF.
        IF member-version IS NOT INITIAL OR member-dateto <> '99991231'.
          entry-supported = abap_false.
        ENDIF.
      ENDLOOP.
      IF count > 1.
        entry-supported = abap_false.
      ENDIF.
      IF entry-supported = abap_false.
        entry-reason = `time or version dependent, which olap4abap does not support yet`.
      ENDIF.
      IF entry-text IS INITIAL.
        entry-text = entry-name.
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_tables.
    result = registered_tables( characteristic ).
    IF result IS NOT INITIAL AND tables_exist( result ) = abap_true AND current_columns( result ) = abap_true.
      RETURN.
    ENDIF.
    IF result IS NOT INITIAL.
      " objects of an older layout, or some of them missing: the copies are BW's data, so the objects are made again
      " under their names (the view first, it reads the closure table) and the next query refills them
      result = tables_of_number( CONV i( substring( val = result-node off = strlen( c_node_prefix ) ) ) ).
      delete_rest_view( result ).
      delete_table( result-node ).
      delete_table( result-closure ).
      DELETE FROM zzxxmla1_hiedir WHERE iobjnm = @characteristic.
    ELSE.
      result = tables_of_number( next_table_number( ) ).
    ENDIF.
    create_table( name        = result-node
                  description = |BW hierarchy nodes { characteristic }|
                  columns     = node_columns( ) ).
    create_table( name        = result-closure
                  description = |BW hierarchy closure { characteristic }|
                  columns     = closure_columns( ) ).
    create_rest_view( characteristic = characteristic tables = result ).
    DATA(row) = VALUE zzxxmla1_hietab( iobjnm        = characteristic
                                       node_table    = result-node
                                       closure_table = result-closure
                                       rest_view     = result-rest_view
                                       rest_ddl      = result-rest_ddl
                                       changed_by    = sy-uname ).
    GET TIME STAMP FIELD row-changed_at.
    MODIFY zzxxmla1_hietab FROM @row.
    COMMIT WORK.
  ENDMETHOD.

  METHOD delete_tables.
    DATA(tables) = registered_tables( characteristic ).
    IF tables IS INITIAL.
      RETURN.
    ENDIF.
    " the view first, it reads the closure table
    delete_rest_view( tables ).
    delete_table( tables-node ).
    delete_table( tables-closure ).
    DELETE FROM zzxxmla1_hiedir WHERE iobjnm = @characteristic.
    DELETE FROM zzxxmla1_hietab WHERE iobjnm = @characteristic.
    COMMIT WORK.
  ENDMETHOD.

  METHOD current_columns.
    DATA(expected) = VALUE string_table( FOR c IN node_columns( ) ( CONV string( c-name ) ) ).
    SELECT fieldname FROM dd03l WHERE tabname = @tables-node AND as4local = 'A'
      ORDER BY position ASCENDING INTO TABLE @DATA(node_fields).
    DATA(actual) = VALUE string_table( FOR f IN node_fields ( CONV string( f-fieldname ) ) ).
    DATA(expected_closure) = VALUE string_table( FOR k IN closure_columns( ) ( CONV string( k-name ) ) ).
    SELECT fieldname FROM dd03l WHERE tabname = @tables-closure AND as4local = 'A'
      ORDER BY position ASCENDING INTO TABLE @DATA(closure_fields).
    DATA(actual_closure) = VALUE string_table( FOR g IN closure_fields ( CONV string( g-fieldname ) ) ).
    result = xsdbool( actual = expected AND actual_closure = expected_closure ).
  ENDMETHOD.

  METHOD delete_table.
    CALL FUNCTION 'RS_DD_DELETE_OBJ'
      EXPORTING
        no_ask               = abap_true
        objname              = name
        objtype              = 'T'
      EXCEPTIONS
        not_executed         = 1
        object_not_found     = 2
        object_not_specified = 3
        permission_failure   = 4
        dialog_needed        = 5
        OTHERS               = 6.
    IF sy-subrc <> 0 AND sy-subrc <> 2.
      refuse( |Table { name } cannot be deleted (RS_DD_DELETE_OBJ: { sy-subrc })| ).
    ENDIF.
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_delete_tadir_entry = abap_true
        wi_test_modus         = abap_false
        wi_tadir_pgmid        = 'R3TR'
        wi_tadir_object       = 'TABL'
        wi_tadir_obj_name     = CONV sobj_name( name )
      EXCEPTIONS
        OTHERS                = 1.
  ENDMETHOD.

  METHOD registered_tables.
    SELECT SINGLE node_table, closure_table, rest_view, rest_ddl FROM zzxxmla1_hietab WHERE iobjnm = @characteristic
      INTO (@result-node, @result-closure, @result-rest_view, @result-rest_ddl).
    IF sy-subrc <> 0.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

  METHOD tables_exist.
    " all three must be active in the DDIC
    SELECT COUNT( * ) FROM dd02l
      WHERE ( tabname = @tables-node OR tabname = @tables-closure OR tabname = @tables-rest_view ) AND as4local = 'A'
      INTO @DATA(found).
    result = xsdbool( found = 3 ).
  ENDMETHOD.

  METHOD current.
    DATA(bw) = bw_state( characteristic = characteristic name = name ).
    DATA(tables) = registered_tables( bw-iobjnm ).
    IF tables IS INITIAL OR tables_exist( tables ) = abap_false.
      refuse( |The hierarchy { name } of { characteristic } has no tables: accept a schema that names it| ).
    ENDIF.
    SELECT SINGLE * FROM zzxxmla1_hiedir WHERE hieid = @bw-hieid AND hiesid = @bw-hiesid AND sver = @bw-sver
      INTO @DATA(directory).
    IF up_to_date( directory = directory bw = bw ) = abap_false.
      lock( bw-hieid ).
      TRY.
          " another query may have refilled it while this one waited
          SELECT SINGLE * FROM zzxxmla1_hiedir WHERE hieid = @bw-hieid AND hiesid = @bw-hiesid AND sver = @bw-sver
            INTO @directory.
          IF up_to_date( directory = directory bw = bw ) = abap_false.
            directory = refill( bw = bw tables = tables bw_tables = bw_tables( bw-iobjnm ) ).
            DATA(refilled) = abap_true.
          ENDIF.
        CLEANUP.
          unlock( bw-hieid ).
      ENDTRY.
      unlock( bw-hieid ).
    ENDIF.
    result = hierarchy_of( directory = directory tables = tables ).
    result-refilled = refilled.
  ENDMETHOD.

  METHOD bw_state.
    SELECT hieid, iobjnm, hienm, version, dateto, norestnodes FROM rshiedir
      WHERE iobjnm = @characteristic AND hienm = @name AND objvers = 'A'
      INTO TABLE @DATA(rows).
    IF rows IS INITIAL.
      refuse( |BW has no active hierarchy { name } of { characteristic }| ).
    ENDIF.
    IF lines( rows ) > 1 OR rows[ 1 ]-version IS NOT INITIAL OR rows[ 1 ]-dateto <> '99991231'.
      refuse( |The hierarchy { name } of { characteristic } is time or version dependent, which olap4abap does not support yet| ).
    ENDIF.
    DATA(row) = rows[ 1 ].
    result = VALUE #( hieid = row-hieid iobjnm = row-iobjnm hienm = row-hienm norestnodes = row-norestnodes ).
    SELECT hiesid, sver, timestmp, rootsid, resttopsid FROM rsrhiedir_olap
      WHERE hieid = @row-hieid AND objvers = 'A' AND deletetimestmp = 0
      INTO TABLE @DATA(olap).
    IF lines( olap ) <> 1.
      refuse( |The hierarchy { name } of { characteristic } has { lines( olap ) } current rows in RSRHIEDIR_OLAP| &&
              |, olap4abap understands exactly one| ).
    ENDIF.
    result-hiesid = olap[ 1 ]-hiesid.
    result-sver = olap[ 1 ]-sver.
    result-timestmp = olap[ 1 ]-timestmp.
    result-root_sid = olap[ 1 ]-rootsid.
    result-rest_top_sid = olap[ 1 ]-resttopsid.
  ENDMETHOD.

  METHOD bw_tables.
    DATA structure TYPE rsinctab.
    DATA node_sids TYPE rshsitab.
    CALL FUNCTION 'RSD_HIETAB_GET_FOR_CHA_BAS'
      EXPORTING
        i_chabasnm = characteristic
      IMPORTING
        e_inctab   = structure
        e_hsitab   = node_sids
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0 OR structure IS INITIAL OR node_sids IS INITIAL.
      refuse( |BW has no hierarchy tables of { characteristic }| ).
    ENDIF.
    result = VALUE #( structure = structure
                      node_sids = node_sids
                      sids      = NEW zzxxmla1_cl_bw_view_gen( )->tables( characteristic )-sids ).
  ENDMETHOD.

  METHOD up_to_date.
    " BW does not change a structure once its SVER is written: a change, also of the not-assigned setting, is a new
    " SVER; the same SVER of another TIMESTMP is BW's SVER given again
    result = xsdbool( directory-sver IS NOT INITIAL
                      AND directory-hiesid = bw-hiesid
                      AND directory-sver = bw-sver
                      AND directory-timestmp = bw-timestmp ).
  ENDMETHOD.

  METHOD stale_copies.
    LOOP AT copies INTO DATA(copy).
      IF NOT line_exists( versions[ hiesid = copy-hiesid sver = copy-sver timestmp = copy-timestmp ] ).
        APPEND copy TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD hierarchy_of.
    DATA(shown) = xsdbool( directory-norestnodes IS INITIAL ).
    result = VALUE #( hieid          = directory-hieid
                      characteristic = directory-iobjnm
                      name           = directory-hienm
                      node_table     = tables-node
                      closure_table  = tables-closure
                      closure        = COND #( WHEN shown = abap_true THEN tables-rest_view ELSE tables-closure )
                      hiesid         = directory-hiesid
                      sver           = directory-sver
                      root_sid       = directory-root_sid
                      rest_top_sid   = directory-rest_top_sid
                      rest_shown     = shown ).
  ENDMETHOD.

  METHOD values_of.
    result = VALUE #(
      sql    = |SELECT "SID" FROM { quote( hierarchy-closure ) } WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?|
      params = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ( NEW i( node_sid ) ) ) ).
  ENDMETHOD.

  METHOD depth.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT COALESCE( MAX( "DEPTH" ), 0 ) FROM { quote( hierarchy-node_table ) } | &&
                |WHERE "HIESID" = ? AND "SVER" = ?|
      columns = 1
      params  = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ) ).
    result = rows[ 1 ][ 1 ].
    IF hierarchy-rest_shown = abap_true AND result < 2.
      result = 2.
    ENDIF.
  ENDMETHOD.

  METHOD level_cardinality.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT COUNT( * ) FROM { quote( hierarchy-node_table ) } | &&
                |WHERE "HIESID" = ? AND "SVER" = ? AND "DEPTH" = ?|
      columns = 1
      params  = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ( NEW i( level ) ) ) ).
    result = rows[ 1 ][ 1 ].
    IF hierarchy-rest_shown = abap_false.
      RETURN.
    ENDIF.
    IF level = 1.
      result = result + 1.
    ELSEIF level = 2.
      DATA(rest) = values_of( hierarchy = hierarchy node_sid = hierarchy-rest_top_sid ).
      rows = zzxxmla1_cl_sql=>query( sql = |SELECT COUNT( * ) FROM ( { rest-sql } ) AS rest| columns = 1
                                     params = rest-params ).
      result = result + rows[ 1 ][ 1 ].
    ENDIF.
  ENDMETHOD.

  METHOD repeated_levels.
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT DISTINCT "DEPTH" FROM { quote( hierarchy-node_table ) } | &&
                |WHERE "HIESID" = ? AND "SVER" = ? AND "DEPTH" > 0 GROUP BY "DEPTH", "SID" HAVING COUNT( * ) > 1 | &&
                |ORDER BY "DEPTH"|
      columns = 1
      params  = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ) ).
    LOOP AT rows INTO DATA(row).
      APPEND CONV i( row[ 1 ] ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD level_column.
    result = |L{ level WIDTH = 2 ALIGN = RIGHT PAD = `0` }_{ part }|.
  ENDMETHOD.

  METHOD levels_sql.
    " a member of depth d is the row n, its member on level k the parent d - k steps up (p1, p2, ...): a level's
    " column is a CASE over n's depth. Parents are inner nodes (negative SIDs; the virtual root's parent 0 is none)
    DATA(node) = quote( hierarchy-node_table ).
    DATA(sver) = zzxxmla1_cl_sql=>literal( CONV string( hierarchy-sver ) ).
    " a leaf is named and captioned as the characteristic's member: by the view's columns, SID 0 too
    DATA(value_name) = |COALESCE( TO_NVARCHAR( v.{ quote( name_column ) } ), TO_NVARCHAR( n."SID" ) )|.
    DATA(value_caption) = COND string( WHEN caption_column IS NOT INITIAL
                                       THEN |COALESCE( TO_NVARCHAR( v.{ quote( caption_column ) } ), { value_name } )| ).
    DATA(columns) = VALUE string_table( ).
    DO depth TIMES.
      DATA(level) = sy-index.
      DATA(sids) = ``.
      DATA(names) = ``.
      DATA(positions) = ``.
      DATA(captions) = ``.
      DO depth - level + 1 TIMES.
        DATA(up) = sy-index - 1.
        DATA(alias) = COND string( WHEN up = 0 THEN `n` ELSE |p{ up }| ).
        DATA(branch) = | WHEN { level + up } THEN |.
        sids = |{ sids }{ branch }{ alias }."SID"|.
        names = names && branch && COND string( WHEN up = 0 THEN |CASE WHEN n."SID" < 0 THEN TO_NVARCHAR( n."NODE_NAME" ) | &&
                                                               |ELSE { value_name } END|
                                              ELSE |TO_NVARCHAR( { alias }."NODE_NAME" )| ).
        positions = |{ positions }{ branch }{ alias }."POS"|.
        " a node is captioned by its node name until the texts of the nodes come (RSTHIENODE)
        captions = captions && branch && COND string( WHEN up = 0 THEN |CASE WHEN n."SID" < 0 THEN TO_NVARCHAR( n."NODE_NAME" ) | &&
                                                                     |ELSE { value_caption } END|
                                                    ELSE |TO_NVARCHAR( { alias }."NODE_NAME" )| ).
      ENDDO.
      APPEND |CASE n."DEPTH"{ sids } END AS { quote( level_column( level = level part = c_level_part-sid ) ) }|
             TO columns.
      APPEND |CASE n."DEPTH"{ names } END AS { quote( level_column( level = level part = c_level_part-name ) ) }|
             TO columns.
      APPEND |CASE n."DEPTH"{ positions } END AS { quote( level_column( level = level part = c_level_part-pos ) ) }|
             TO columns.
      IF caption_column IS NOT INITIAL.
        APPEND |CASE n."DEPTH"{ captions } END AS { quote( level_column( level = level part = c_level_part-caption ) ) }|
               TO columns.
      ENDIF.
    ENDDO.
    DATA(joins) = |LEFT OUTER JOIN { quote( value_table ) } AS v ON v.{ quote( sid_column ) } = n."SID" AND n."SID" >= 0|.
    DO depth - 1 TIMES.
      DATA(parent) = |p{ sy-index }|.
      DATA(child) = COND string( WHEN sy-index = 1 THEN `n` ELSE |p{ sy-index - 1 }| ).
      joins = |{ joins } LEFT OUTER JOIN { node } AS { parent } ON { parent }."HIESID" = n."HIESID" | &&
              |AND { parent }."SVER" = n."SVER" AND { parent }."SID" = { child }."PARENT_SID" AND { parent }."SID" < 0|.
    ENDDO.
    result = |SELECT { concat_lines_of( table = columns sep = `, ` ) } FROM { node } AS n { joins } | &&
             |WHERE n."HIESID" = { hierarchy-hiesid } AND n."SVER" = { sver } AND n."DEPTH" BETWEEN 1 AND { depth }|.
    IF hierarchy-rest_shown = abap_false.
      RETURN.
    ENDIF.

    " REST_H after the roots, its values below it: the closure's rows under it
    DATA(empty) = |CAST( NULL AS INTEGER ), CAST( NULL AS NVARCHAR( 1 ) ), CAST( NULL AS INTEGER )| &&
                  COND string( WHEN caption_column IS NOT INITIAL THEN |, CAST( NULL AS NVARCHAR( 1 ) )| ).
    DATA(below) = ``.
    DO depth - 2 TIMES.
      below = |{ below }, { empty }|.
    ENDDO.
    DATA(rest) = |{ hierarchy-rest_top_sid }, '{ c_rest_node_name }', { c_rest_listno }| &&
                 COND string( WHEN caption_column IS NOT INITIAL THEN |, '{ c_rest_node_name }'| ).
    value_name = replace( val = value_name sub = `n."SID"` with = `r."SID"` occ = 0 ).
    value_caption = replace( val = value_caption sub = `n."SID"` with = `r."SID"` occ = 0 ).
    DATA(value) = |r."SID", { value_name }, { c_rest_listno } + ROW_NUMBER( ) OVER ( ORDER BY { value_name } )| &&
                  COND string( WHEN caption_column IS NOT INITIAL THEN |, { value_caption }| ).
    result = |{ result } UNION ALL SELECT { rest }, { empty }{ below } FROM DUMMY| &&
             | UNION ALL SELECT { rest }, { value }{ below } | &&
             |FROM { quote( hierarchy-closure ) } AS r | &&
             |LEFT OUTER JOIN { quote( value_table ) } AS v ON v.{ quote( sid_column ) } = r."SID" | &&
             |WHERE r."HIESID" = { hierarchy-hiesid } AND r."SVER" = { sver } | &&
             |AND r."ANCESTOR_SID" = { hierarchy-rest_top_sid }|.
  ENDMETHOD.

  METHOD lock.
    DATA(key) = CONV rstable-varkey( hieid ).
    DO c_lock_attempts TIMES.
      CALL FUNCTION 'ENQUEUE_E_TABLE'
        EXPORTING
          mode_rstable   = 'E'
          tabname        = 'ZZXXMLA1_HIEDIR'
          varkey         = key
          _wait          = abap_true
        EXCEPTIONS
          foreign_lock   = 1
          system_failure = 2
          OTHERS         = 3.
      IF sy-subrc = 0.
        RETURN.
      ELSEIF sy-subrc <> 1.
        EXIT.
      ENDIF.
    ENDDO.
    refuse( |The hierarchy { hieid } is being refilled by another query; try again| ).
  ENDMETHOD.

  METHOD unlock.
    DATA(key) = CONV rstable-varkey( hieid ).
    CALL FUNCTION 'DEQUEUE_E_TABLE'
      EXPORTING
        mode_rstable = 'E'
        tabname      = 'ZZXXMLA1_HIEDIR'
        varkey       = key.
  ENDMETHOD.

  METHOD refill.
    DATA versions TYPE ty_t_version.
    DATA copies TYPE ty_t_directory.
    SELECT * FROM zzxxmla1_hiedir WHERE hieid = @bw-hieid INTO TABLE @copies.
    SELECT hiesid, sver, timestmp FROM rsrhiedir_olap WHERE hieid = @bw-hieid AND objvers = 'A'
      INTO CORRESPONDING FIELDS OF TABLE @versions.
    DATA(key) = VALUE zzxxmla1_cl_sql=>ty_t_param( ( NEW i( bw-hiesid ) ) ( NEW string( bw-sver ) ) ).
    TRY.
        " the copies of versions BW does not keep any more: no query reads them
        DATA(stales) = stale_copies( copies = copies versions = versions ).
        LOOP AT stales INTO DATA(stale).
          delete_copy( tables = tables hiesid = stale-hiesid sver = stale-sver ).
          DELETE FROM zzxxmla1_hiedir WHERE hieid = @stale-hieid AND hiesid = @stale-hiesid AND sver = @stale-sver.
        ENDLOOP.
        " rows of this SVER that no directory row names (a refill that did not finish)
        delete_copy( tables = tables hiesid = bw-hiesid sver = bw-sver ).
        zzxxmla1_cl_sql=>execute( sql    = nodes_sql( tables = tables bw_tables = bw_tables )
                                  params = VALUE #( BASE key ( NEW i( bw-root_sid ) ) ) ).
        zzxxmla1_cl_sql=>execute( sql = end_pos_sql( tables ) params = key ).
        zzxxmla1_cl_sql=>execute( sql = closure_sql( tables ) params = VALUE #( BASE key ( LINES OF key ) ) ).
        check( bw = bw tables = tables bw_tables = bw_tables ).
      CLEANUP.
        ROLLBACK WORK.
    ENDTRY.
    result = VALUE #( hiesid       = bw-hiesid
                      sver         = bw-sver
                      hieid        = bw-hieid
                      iobjnm       = bw-iobjnm
                      hienm        = bw-hienm
                      timestmp     = bw-timestmp
                      norestnodes  = bw-norestnodes
                      root_sid     = bw-root_sid
                      rest_top_sid = bw-rest_top_sid
                      filled_by    = sy-uname ).
    GET TIME STAMP FIELD result-filled_at.
    MODIFY zzxxmla1_hiedir FROM @result.
    COMMIT WORK.
  ENDMETHOD.

  METHOD delete_copy.
    DATA(key) = VALUE zzxxmla1_cl_sql=>ty_t_param( ( NEW i( hiesid ) ) ( NEW string( sver ) ) ).
    zzxxmla1_cl_sql=>execute( sql = |DELETE FROM { quote( tables-node ) } WHERE "HIESID" = ? AND "SVER" = ?| params = key ).
    zzxxmla1_cl_sql=>execute( sql = |DELETE FROM { quote( tables-closure ) } WHERE "HIESID" = ? AND "SVER" = ?| params = key ).
  ENDMETHOD.

  METHOD check.
    DATA(characteristic) = NEW string( bw-iobjnm ).
    DATA(hiesid) = NEW i( bw-hiesid ).
    DATA(sver) = NEW string( bw-sver ).
    DATA(rows) = zzxxmla1_cl_sql=>query( sql     = node_and_leaf_sql( tables )
                                         columns = 2
                                         params  = VALUE #( ( characteristic ) ( hiesid ) ( sver ) ( characteristic ) ) ).
    IF rows IS NOT INITIAL.
      refuse( |The hierarchy { bw-hienm } of { bw-iobjnm } has { rows[ 1 ][ 2 ] } both as an inner node and as a | &&
              |leaf, which olap4abap refuses| ).
    ENDIF.
    rows = zzxxmla1_cl_sql=>query( sql     = different_subtrees_sql( tables )
                                   columns = 2
                                   params  = VALUE #( ( hiesid ) ( sver ) ( characteristic ) ) ).
    IF rows IS NOT INITIAL.
      refuse( |The hierarchy { bw-hienm } of { bw-iobjnm } has { rows[ 1 ][ 2 ] } more than once with different | &&
              |subtrees, which olap4abap refuses| ).
    ENDIF.
    rows = zzxxmla1_cl_sql=>query( sql     = differences_sql( tables = tables bw_tables = bw_tables )
                                   columns = 4
                                   params  = VALUE #( ( hiesid ) ( sver ) ( hiesid ) ( sver ) ) ).
    IF rows IS NOT INITIAL.
      DATA(row) = rows[ 1 ].
      refuse( |The copy of the hierarchy { bw-hienm } of { bw-iobjnm } differs from BW's: node { row[ 2 ] } | &&
              |(SID { row[ 1 ] }) has { row[ 3 ] } values, BW's { row[ 4 ] }| ).
    ENDIF.
  ENDMETHOD.

  METHOD nodes_sql.
    " the root row of BW (LISTNO 0, the virtual root ROOTSID) and the numbered rows but the not-assigned ones; the
    " correction rows (LISTNO 0) are left out
    DATA(listno) = |ROW_NUMBER( ) OVER ( ORDER BY i."LISTNO", i."SUCC" ) - 1|.
    result = |INSERT INTO { quote( tables-node ) } ( "HIESID", "SVER", "PARENT_SID", "SID", "DEPTH", "POS", "END_POS", | &&
             |"NODE_IOBJ", "NODE_NAME", "VALUE_SID" ) | &&
             |SELECT i."HIESID", i."SVER", CASE WHEN i."LISTNO" = 0 THEN 0 ELSE i."PRED" END, i."SUCC", | &&
             |CAST( i."TLEVEL" AS INTEGER ), { listno }, { listno }, | &&
             |COALESCE( k."NIOBJNM", '' ), COALESCE( k."NODENAME", '' ), COALESCE( k."OSID", 0 ) | &&
             |FROM { quote( bw_tables-structure ) } AS i | &&
             |LEFT OUTER JOIN { quote( bw_tables-node_sids ) } AS k ON k."HIESID" = i."HIESID" AND k."SID" = i."SUCC" | &&
             |WHERE i."HIESID" = ? AND i."SVER" = ? | &&
             |AND ( ( i."LISTNO" > 0 AND i."LISTNO" < { c_rest_listno } ) OR ( i."LISTNO" = 0 AND i."SUCC" = ? ) )|.
  ENDMETHOD.

  METHOD end_pos_sql.
    " an inner node's subtree ends before the next row at its depth or above, else at the last row
    DATA(node) = quote( tables-node ).
    result = |UPDATE { node } SET "END_POS" = COALESCE( | &&
             |( SELECT MIN( m."POS" ) FROM { node } AS m WHERE m."HIESID" = { node }."HIESID" AND m."SVER" = { node }."SVER" | &&
             |AND m."POS" > { node }."POS" AND m."DEPTH" <= { node }."DEPTH" ), | &&
             |( SELECT MAX( x."POS" ) + 1 FROM { node } AS x WHERE x."HIESID" = { node }."HIESID" AND x."SVER" = { node }."SVER" ) ) - 1 | &&
             |WHERE "HIESID" = ? AND "SVER" = ? AND "SID" < 0|.
  ENDMETHOD.

  METHOD closure_sql.
    " per inner node the distinct leaves of its subtree, per leaf (a value under two parents once) its identity row
    DATA(node) = quote( tables-node ).
    result = |INSERT INTO { quote( tables-closure ) } ( "HIESID", "SVER", "ANCESTOR_SID", "SID" ) | &&
             |SELECT DISTINCT n."HIESID", n."SVER", n."SID", l."SID" FROM { node } AS n | &&
             |INNER JOIN { node } AS l ON l."HIESID" = n."HIESID" AND l."SVER" = n."SVER" AND l."POS" > n."POS" AND l."POS" <= n."END_POS" | &&
             |WHERE n."HIESID" = ? AND n."SVER" = ? AND n."SID" < 0 AND l."SID" >= 0 | &&
             |UNION ALL SELECT DISTINCT "HIESID", "SVER", "SID", "SID" FROM { node } | &&
             |WHERE "HIESID" = ? AND "SVER" = ? AND "SID" >= 0|.
  ENDMETHOD.

  METHOD node_and_leaf_sql.
    " a value that is a (postable) inner node and a leaf elsewhere than as the node's own first leaf
    DATA(node) = quote( tables-node ).
    result = |SELECT l."SID", MIN( v."NODE_NAME" ) FROM { node } AS l | &&
             |INNER JOIN { node } AS v ON v."HIESID" = l."HIESID" AND v."SVER" = l."SVER" AND v."SID" < 0 AND v."NODE_IOBJ" = ? | &&
             |AND v."VALUE_SID" = l."SID" | &&
             |WHERE l."HIESID" = ? AND l."SVER" = ? AND l."SID" >= 0 AND NOT EXISTS ( SELECT 1 FROM { node } AS p | &&
             |WHERE p."HIESID" = l."HIESID" AND p."SVER" = l."SVER" AND p."SID" = l."PARENT_SID" AND p."NODE_IOBJ" = ? | &&
             |AND p."VALUE_SID" = l."SID" ) | &&
             |GROUP BY l."SID" ORDER BY l."SID"|.
  ENDMETHOD.

  METHOD different_subtrees_sql.
    " every occurrence's values are a part of all occurrences' values: they are the same set for each exactly if
    " their sizes add up to the number of occurrences times the size of all; the subtrees' sizes must be equal too
    DATA(node) = quote( tables-node ).
    result = |SELECT v."VALUE_SID", MIN( v."NODE_NAME" ) FROM { node } AS v | &&
             |LEFT OUTER JOIN { quote( tables-closure ) } AS c ON c."HIESID" = v."HIESID" AND c."SVER" = v."SVER" | &&
             |AND c."ANCESTOR_SID" = v."SID" | &&
             |WHERE v."HIESID" = ? AND v."SVER" = ? AND v."SID" < 0 AND v."NODE_IOBJ" = ? | &&
             |GROUP BY v."VALUE_SID" HAVING COUNT( DISTINCT v."SID" ) > 1 | &&
             |AND ( COUNT( DISTINCT c."SID" ) * COUNT( DISTINCT v."SID" ) <> COUNT( c."SID" ) | &&
             |OR MIN( v."END_POS" - v."POS" ) <> MAX( v."END_POS" - v."POS" ) ) | &&
             |ORDER BY v."VALUE_SID"|.
  ENDMETHOD.

  METHOD differences_sql.
    " BW's distinct values of a node: its leaf rows (an interval's values each) plus the factors of the correction
    " rows (LISTNO 0) of the node and of every inner node below it: each corrects the values reached more than once
    " below its PRED that the corrections below did not (ZCLPAT_PRG's PROGRAMS: 1,071 rows, -439 at it, -154 below,
    " 478 values); BW has none for its virtual root (DEPTH 0), whose values are its roots' values
    DATA(node) = quote( tables-node ).
    DATA(ours) = |( SELECT COUNT( * ) FROM { quote( tables-closure ) } AS c | &&
                 |WHERE c."HIESID" = n."HIESID" AND c."SVER" = n."SVER" AND c."ANCESTOR_SID" = n."SID" )|.
    DATA(theirs) = |( SELECT COUNT( * ) FROM { node } AS l WHERE l."HIESID" = n."HIESID" AND l."SVER" = n."SVER" | &&
                   |AND l."POS" > n."POS" AND l."POS" <= n."END_POS" AND l."SID" >= 0 ) + | &&
                   |( SELECT COALESCE( SUM( i."FACTOR" ), 0 ) FROM { quote( bw_tables-structure ) } AS i | &&
                   |INNER JOIN { node } AS m ON m."HIESID" = n."HIESID" AND m."SVER" = n."SVER" AND m."SID" = i."PRED" | &&
                   |AND m."POS" >= n."POS" AND m."POS" <= n."END_POS" | &&
                   |WHERE i."HIESID" = ? AND i."SVER" = ? AND i."LISTNO" = 0 AND i."SUCC" >= 0 )|.
    result = |SELECT * FROM ( SELECT n."SID", n."NODE_NAME", { ours } AS "OURS", { theirs } AS "THEIRS" | &&
             |FROM { node } AS n WHERE n."HIESID" = ? AND n."SVER" = ? AND n."SID" < 0 AND n."DEPTH" > 0 ) AS d | &&
             |WHERE d."OURS" <> d."THEIRS" ORDER BY d."SID" DESC|.
  ENDMETHOD.

  METHOD node_columns.
    result = VALUE #( ( name = 'HIESID'     rollname = 'RSRHIESID'           key = abap_true )
                      ( name = 'SVER'       rollname = 'RSRSVER'             key = abap_true )
                      ( name = 'PARENT_SID' rollname = 'RSSID'               key = abap_true )
                      ( name = 'SID'        rollname = 'RSSID'               key = abap_true )
                      ( name = 'DEPTH'      rollname = 'INT4' )
                      ( name = 'POS'        rollname = 'INT4' )
                      ( name = 'END_POS'    rollname = 'INT4' )
                      ( name = 'NODE_IOBJ'  rollname = 'RSNIOBJNM' )
                      ( name = 'NODE_NAME'  rollname = 'RSSHNODENAME_MAXLEN' )
                      ( name = 'VALUE_SID'  rollname = 'RSSID' ) ).
  ENDMETHOD.

  METHOD closure_columns.
    result = VALUE #( ( name = 'HIESID'       rollname = 'RSRHIESID' key = abap_true )
                      ( name = 'SVER'         rollname = 'RSRSVER'   key = abap_true )
                      ( name = 'ANCESTOR_SID' rollname = 'RSSID'     key = abap_true )
                      ( name = 'SID'          rollname = 'RSSID'     key = abap_true ) ).
  ENDMETHOD.

  METHOD create_table.
    DATA fields TYPE STANDARD TABLE OF dd03p WITH EMPTY KEY.
    LOOP AT columns INTO DATA(column).
      APPEND VALUE #( tabname   = name
                      fieldname = column-name
                      position  = sy-tabix
                      keyflag   = column-key
                      rollname  = column-rollname
                      notnull   = abap_true
                      comptype  = 'E' ) TO fields.
    ENDLOOP.
    DATA(header) = VALUE dd02v( tabname    = name
                                ddlanguage = 'E'
                                tabclass   = 'TRANSP'
                                ddtext     = description
                                masterlang = 'E'
                                contflag   = 'A'
                                exclass    = '1' ).
    DATA(technical) = VALUE dd09l( tabname  = name
                                   as4local = 'A'
                                   tabkat   = '0'
                                   tabart   = 'APPL1'
                                   bufallow = 'N' ).
    CALL FUNCTION 'TR_TADIR_INTERFACE'
      EXPORTING
        wi_test_modus     = abap_false
        wi_tadir_pgmid    = 'R3TR'
        wi_tadir_object   = 'TABL'
        wi_tadir_obj_name = CONV sobj_name( name )
        wi_tadir_devclass = package
      EXCEPTIONS
        OTHERS            = 1.
    IF sy-subrc <> 0.
      refuse( |Table { name } cannot be registered in package { package }| ).
    ENDIF.
    CALL FUNCTION 'DDIF_TABL_PUT'
      EXPORTING
        name      = name
        dd02v_wa  = header
        dd09l_wa  = technical
      TABLES
        dd03p_tab = fields
      EXCEPTIONS
        OTHERS    = 1.
    IF sy-subrc <> 0.
      refuse( |Table { name } cannot be written to the DDIC| ).
    ENDIF.
    DATA rc TYPE sysubrc.
    CALL FUNCTION 'DDIF_TABL_ACTIVATE'
      EXPORTING
        name     = name
        auth_chk = abap_false
      IMPORTING
        rc       = rc
      EXCEPTIONS
        OTHERS   = 1.
    IF sy-subrc <> 0 OR rc > 4.
      refuse( |Table { name } cannot be activated (return code { rc })| ).
    ENDIF.
  ENDMETHOD.

  METHOD create_rest_view.
    DATA(sid_table) = NEW zzxxmla1_cl_bw_view_gen( )->tables( characteristic )-sids.
    IF sid_table IS INITIAL.
      refuse( |BW has no SID table of { characteristic }| ).
    ENDIF.
    DATA(description) = rest_view_description( characteristic ).
    TRY.
        ddl_handler( )->save( name         = tables-rest_ddl
                              put_state    = 'N'
                              ddddlsrcv_wa = VALUE #( ddlname    = tables-rest_ddl
                                                      ddlanguage = sy-langu
                                                      ddtext     = description
                                                      source     = rest_view_source( characteristic = characteristic
                                                                                     tables         = tables
                                                                                     sid_table      = sid_table ) ) ).
        cl_dd_ddl_handler=>if_dd_ddl_handler~write_tadir( objectname = tables-rest_ddl
                                                          devclass   = package
                                                          prid       = -1 ).
        ddl_handler( )->activate( tables-rest_ddl ).
      CATCH cx_dd_ddl_exception INTO DATA(error).
        refuse( |View { tables-rest_ddl } cannot be activated: { error->get_text( ) }| ).
    ENDTRY.
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @tables-rest_view AND as4local = 'A' INTO @DATA(active).
    IF sy-subrc <> 0.
      refuse( |View { tables-rest_ddl } cannot be activated| ).
    ENDIF.
  ENDMETHOD.

  METHOD delete_rest_view.
    SELECT SINGLE ddlname FROM ddddlsrc WHERE ddlname = @tables-rest_ddl INTO @DATA(found).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    TRY.
        ddl_handler( )->delete( found ).
      CATCH cx_dd_ddl_exception INTO DATA(error).
        refuse( |View { tables-rest_ddl } cannot be deleted: { error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD rest_view_source.
    " the closure table's rows, then per copy that shows the not-assigned node (NORESTNODES not X) and SID of the SID
    " table under no leaf (none of the All member's rows): the not-assigned node, the All member and the identity
    " row. The directory is joined to the SID table by a condition that holds for every pair (a hierarchy's SIDs are
    " negative, the characteristic's positive), as 7.50's CDS has no cross join; the anti-join is a left outer join
    " where none is found, as it has no NOT EXISTS
    DATA(nl) = cl_abap_char_utilities=>newline.
    DATA(closure) = to_lower( tables-closure ).
    DATA(rest) = ``.
    DATA(ancestors) = VALUE string_table( ( `d.rest_top_sid` ) ( `d.root_sid` ) ( `s.sid` ) ).
    LOOP AT ancestors INTO DATA(ancestor).
      rest = rest &&
             |union all select from zzxxmla1_hiedir as d| && nl &&
             |  inner join { to_lower( sid_table ) } as s on s.sid > d.root_sid| && nl &&
             |  left outer join { closure } as r on r.hiesid = d.hiesid and r.sver = d.sver | &&
             |and r.ancestor_sid = d.root_sid and r.sid = s.sid| && nl &&
             |\{| && nl &&
             |  d.hiesid,| && nl &&
             |  d.sver,| && nl &&
             |  { ancestor } as ancestor_sid,| && nl &&
             |  s.sid| && nl &&
             |\}| && nl &&
             |where d.iobjnm = '{ characteristic }' and d.norestnodes <> 'X' and r.sid is null| && nl.
    ENDLOOP.
    result = |@AbapCatalog.sqlViewName: '{ tables-rest_view }'| && nl &&
             |@AbapCatalog.compiler.compareFilter: true| && nl &&
             |@AccessControl.authorizationCheck: #NOT_REQUIRED| && nl &&
             |@EndUserText.label: '{ rest_view_description( characteristic ) }'| && nl &&
             |define view { tables-rest_ddl }| && nl &&
             |  as select from { closure } as c| && nl &&
             |\{| && nl &&
             |  c.hiesid,| && nl &&
             |  c.sver,| && nl &&
             |  c.ancestor_sid,| && nl &&
             |  c.sid| && nl &&
             |\}| && nl &&
             rest.
  ENDMETHOD.

  METHOD rest_view_description.
    result = |BW hierarchy closure { characteristic }: with not assigned|.
  ENDMETHOD.

  METHOD ddl_handler.
    IF handler IS NOT BOUND.
      handler = cl_dd_ddl_handler_factory=>create( ).
    ENDIF.
    result = handler.
  ENDMETHOD.

  METHOD next_table_number.
    DATA(highest) = 0.
    DATA(node_pattern) = |{ c_node_prefix }%|.
    DATA(closure_pattern) = |{ c_closure_prefix }%|.
    SELECT tabname FROM dd02l
      WHERE ( tabname LIKE @node_pattern OR tabname LIKE @closure_pattern )
      INTO TABLE @DATA(names).
    LOOP AT names INTO DATA(name).
      DATA(digits) = substring( val = name-tabname off = strlen( c_node_prefix ) ).
      IF digits CO '0123456789' AND strlen( digits ) = 7.
        highest = nmax( val1 = highest val2 = CONV i( digits ) ).
      ENDIF.
    ENDLOOP.
    SELECT node_table FROM zzxxmla1_hietab INTO TABLE @DATA(registered).
    LOOP AT registered INTO DATA(table).
      digits = substring( val = table-node_table off = strlen( c_node_prefix ) ).
      IF digits CO '0123456789' AND strlen( digits ) = 7.
        highest = nmax( val1 = highest val2 = CONV i( digits ) ).
      ENDIF.
    ENDLOOP.
    result = highest + 1.
  ENDMETHOD.

  METHOD tables_of_number.
    result = VALUE #( node      = table_name( prefix = c_node_prefix number = number )
                      closure   = table_name( prefix = c_closure_prefix number = number )
                      rest_view = table_name( prefix = c_rest_view_prefix number = number )
                      rest_ddl  = table_name( prefix = c_rest_ddl_prefix number = number ) ).
  ENDMETHOD.

  METHOD table_name.
    result = |{ prefix }{ number WIDTH = 7 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD quote.
    result = zzxxmla1_cl_sql=>quote( identifier ).
  ENDMETHOD.

  METHOD refuse.
    RAISE EXCEPTION TYPE zzxxmla1_cx_bw_hierarchy
      EXPORTING
        error_message = text.
  ENDMETHOD.

ENDCLASS.
