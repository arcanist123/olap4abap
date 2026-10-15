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
"! hierarchies, part one): per InfoObject a node table and a closure table holding all of its hierarchies, as BW's
"! SID structure /BIC/I of the characteristic does, and per hierarchy a row of the directory ZZXXMLA1_HIEDIR.
"! - Node table (ZZXXMLA1H followed by 7 digits): a row per occurrence, the shared subtrees expanded as BW's SID
"!   structure /BIC/I holds them, keyed by HIESID, SVER, PARENT_SID and SID. An inner node has its own negative node SID of
"!   /BIC/K (also each occurrence inside an expanded link, the postable nodes and the virtual root ROOTSID of
"!   RSRHIEDIR_OLAP, the All member, PARENT_SID 0, DEPTH 0, POS 0), a leaf the characteristic's SID (a leaf occurrence
"!   is PARENT_SID and SID). DEPTH is BW's TLEVEL, POS the depth-first number (BW's LISTNO; the values of an interval,
"!   which share its LISTNO, by SID), END_POS the last POS of the subtree. NODE_IOBJ and NODE_NAME are BW's node name
"!   (0HIER_NODE and the text node's name, or the characteristic and the key of a postable node, whose own value
"!   VALUE_SID is its first leaf); a leaf is named by the characteristic's view.
"! - Closure table (ZZXXMLA1C, the same digits): per inner node occurrence the distinct SIDs of the leaves below it,
"!   keyed by HIESID, SVER, ANCESTOR_SID and SID, so that a value reached by two paths counts once. A leaf member needs no
"!   row: it is its SID.
"! - A copy is keyed by BW's HIESID and SVER (RSRHIEDIR_OLAP), so that it compares with /BIC/I row by row: BW does
"!   not change a structure once its SVER is written, a change is a new SVER (up to 33 per hierarchy, then given
"!   again). A refill writes the new SVER next to the current one, commits and switches the directory row; the rows
"!   of the SVER before are deleted by the refill after next, so a query that read the directory row before keeps
"!   its rows (HANA's read consistency is per statement, not per query).
"! - Not assigned: the values of the characteristic's SID table under no leaf are not copied; they are read live
"!   (values_of the rest node REST_H, RESTTOPSID), so that they follow master data loads. Whether the hierarchy shows
"!   them is BW's setting, RSHIEDIR-NORESTNODES (the UI offers no switch).
"! The tables are DDIC tables in $TMP (as the generated views; ADBC's tables need HANA's enterprise license and are
"! hard to transport), client-independent as BW's, created by create_tables when a schema that names a hierarchy of
"! the InfoObject is accepted, never by a query. A query calls current: one key read each of the directory and
"! RSRHIEDIR_OLAP; when the copy is not one of BW's current row (HIESID, SVER), it is refilled
"! under the lock ENQUEUE_E_TABLE on ZZXXMLA1_HIEDIR, which another query of the hierarchy waits for. The refill stays
"! in the database (INSERT ... SELECT from /BIC/I and /BIC/K) and refuses, as a fault of the query
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
    "! The node name of BW's text nodes and of the not-assigned node (/BIC/K-NIOBJNM).
    CONSTANTS c_text_node TYPE rsniobjnm VALUE '0HIER_NODE'.

    TYPES:
      "! the generated tables of an InfoObject
      BEGIN OF ty_tables,
        node    TYPE tabname,
        closure TYPE tabname,
      END OF ty_tables.
    TYPES:
      "! a hierarchy's current copy, as a query reads it: its tables, BW's HIESID and SVER it is a copy of (to bind
      "! in each statement), the SIDs of its All member and of its not-assigned node, and whether it shows that node
      BEGIN OF ty_hierarchy,
        hieid          TYPE rshieid,
        characteristic TYPE rsiobjnm,
        name           TYPE rshienm,
        node_table     TYPE tabname,
        closure_table  TYPE tabname,
        sid_table      TYPE tabname,
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

    "! package: the package new tables are created in.
    METHODS constructor
      IMPORTING package TYPE devclass DEFAULT c_default_package.
    "! Creates the node and closure tables of an InfoObject if it has none (accept of a schema that names one of its
    "! hierarchies); an InfoObject that has them keeps them.
    METHODS create_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! The current copy of a hierarchy of a characteristic (the basic one, RSHIEDIR-IOBJNM), refilled first if BW's
    "! is newer. Raises ZZXXMLA1_CX_BW_HIERARCHY.
    METHODS current
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
      RETURNING VALUE(result)  TYPE ty_hierarchy.
    "! The statement of the SIDs below a node of the copy, one column SID: the closure's rows of the node; for the
    "! not-assigned node the values of the SID table under no leaf, read live; for the All member, when the hierarchy
    "! shows the not-assigned node, every value of the SID table.
    CLASS-METHODS values_of
      IMPORTING hierarchy     TYPE ty_hierarchy
                node_sid      TYPE i
      RETURNING VALUE(result) TYPE ty_statement.

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

    "! BW's current state of a hierarchy: its row of RSHIEDIR (time-independent, not version dependent) and its
    "! current row of RSRHIEDIR_OLAP (DELETETIMESTMP 0, which must be one).
    METHODS bw_state
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
      RETURNING VALUE(result)  TYPE ty_bw_state.
    METHODS bw_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_bw_tables.
    METHODS registered_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! Whether the directory row is a copy of BW's current state.
    CLASS-METHODS up_to_date
      IMPORTING directory     TYPE ty_directory
                bw            TYPE ty_bw_state
      RETURNING VALUE(result) TYPE abap_bool.
    "! The hierarchy as a query reads it from its directory row.
    CLASS-METHODS hierarchy_of
      IMPORTING directory     TYPE ty_directory
                tables        TYPE ty_tables
                bw_tables     TYPE ty_bw_tables
      RETURNING VALUE(result) TYPE ty_hierarchy.
    METHODS lock
      IMPORTING hieid TYPE rshieid.
    METHODS unlock
      IMPORTING hieid TYPE rshieid.
    "! Writes the copy of BW's current SVER, checks it, commits and switches the directory row; a refusal rolls back.
    METHODS refill
      IMPORTING bw            TYPE ty_bw_state
                directory     TYPE ty_directory
                tables        TYPE ty_tables
                bw_tables     TYPE ty_bw_tables
      RETURNING VALUE(result) TYPE ty_directory.
    "! Deletes the rows of a copy: of one HIESID and SVER, or of every SVER of a HIESID.
    METHODS delete_copy
      IMPORTING tables TYPE ty_tables
                hiesid TYPE i
                sver   TYPE rsrsver OPTIONAL.
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
    "! closure: HIESID, SVER
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
    "! the next number after the highest one of a generated node or closure table
    METHODS next_table_number
      RETURNING VALUE(result) TYPE i.
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
    " the plain hierarchies of the clinic demo: tables, copy and BW's counts, tab-separated for
    " scripts/hierarchy_copy_test.py
    SELECT iobjnm, hienm FROM rshiedir
      WHERE iobjnm IN ('ZCLDIAG', 'ZCLPAT', 'ZCLSERV') AND objvers = 'A' AND version = ''
      ORDER BY iobjnm ASCENDING, hienm ASCENDING
      INTO TABLE @DATA(hierarchies).
    LOOP AT hierarchies INTO DATA(row).
      TRY.
          DATA(tables) = create_tables( row-iobjnm ).
          GET RUN TIME FIELD DATA(started).
          DATA(hierarchy) = current( characteristic = row-iobjnm name = row-hienm ).
          GET RUN TIME FIELD DATA(stopped).
          DATA(hiesid) = NEW i( hierarchy-hiesid ).
          DATA(sver) = NEW string( hierarchy-sver ).
          DATA(counts) = zzxxmla1_cl_sql=>query(
            sql     = |SELECT ( SELECT COUNT( * ) FROM { quote( tables-node ) } WHERE "HIESID" = ? AND "SVER" = ? ), | &&
                      |( SELECT COUNT( * ) FROM { quote( tables-node ) } WHERE "HIESID" = ? AND "SVER" = ? AND "SID" < 0 ), | &&
                      |( SELECT COUNT( * ) FROM { quote( tables-closure ) } WHERE "HIESID" = ? AND "SVER" = ? ), | &&
                      |( SELECT MAX( "DEPTH" ) FROM { quote( tables-node ) } WHERE "HIESID" = ? AND "SVER" = ? ) FROM DUMMY|
            columns = 4
            params  = VALUE #( ( hiesid ) ( sver ) ( hiesid ) ( sver ) ( hiesid ) ( sver ) ( hiesid ) ( sver ) ) ).
          DATA(root) = values_of( hierarchy = hierarchy node_sid = hierarchy-root_sid ).
          DATA(rest) = values_of( hierarchy = hierarchy node_sid = hierarchy-rest_top_sid ).
          DATA(root_count) = lines( zzxxmla1_cl_sql=>query( sql = root-sql columns = 1 params = root-params ) ).
          DATA(rest_count) = COND i( WHEN hierarchy-rest_shown = abap_true
                                     THEN lines( zzxxmla1_cl_sql=>query( sql = rest-sql columns = 1 params = rest-params ) ) ).
          DATA(line) = counts[ 1 ].
          out->write( |{ row-iobjnm }\t{ row-hienm }\tOK\t{ tables-node }\t{ tables-closure }\t| &&
                      |{ hierarchy-hiesid }/{ hierarchy-sver }\t{ hierarchy-refilled }\t{ hierarchy-root_sid }\t| &&
                      |{ hierarchy-rest_top_sid }\t{ hierarchy-rest_shown }\t{ line[ 1 ] }\t{ line[ 2 ] }\t| &&
                      |{ line[ 3 ] }\t{ line[ 4 ] }\t{ root_count }\t{ rest_count }\t{ stopped - started }| ).
        CATCH zzxxmla1_cx_bw_hierarchy zzxxmla1_cx_sql INTO DATA(error).
          out->write( |{ row-iobjnm }\t{ row-hienm }\tERROR\t{ error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD create_tables.
    result = registered_tables( characteristic ).
    IF result IS NOT INITIAL AND current_columns( result ) = abap_true.
      RETURN.
    ENDIF.
    IF result IS NOT INITIAL.
      " tables of an older layout: the copies are BW's data, so the tables are made again under their names and the
      " next query refills them
      delete_table( result-node ).
      delete_table( result-closure ).
      DELETE FROM zzxxmla1_hiedir WHERE iobjnm = @characteristic.
    ELSE.
      DATA(number) = next_table_number( ).
      result = VALUE #( node    = table_name( prefix = c_node_prefix number = number )
                        closure = table_name( prefix = c_closure_prefix number = number ) ).
    ENDIF.
    create_table( name        = result-node
                  description = |BW hierarchy nodes { characteristic }|
                  columns     = node_columns( ) ).
    create_table( name        = result-closure
                  description = |BW hierarchy closure { characteristic }|
                  columns     = closure_columns( ) ).
    DATA(row) = VALUE zzxxmla1_hietab( iobjnm        = characteristic
                                       node_table    = result-node
                                       closure_table = result-closure
                                       changed_by    = sy-uname ).
    GET TIME STAMP FIELD row-changed_at.
    MODIFY zzxxmla1_hietab FROM @row.
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
    SELECT SINGLE node_table, closure_table FROM zzxxmla1_hietab WHERE iobjnm = @characteristic
      INTO (@result-node, @result-closure).
    IF sy-subrc <> 0.
      CLEAR result.
      RETURN.
    ENDIF.
    " both must be active tables of the DDIC
    SELECT COUNT( * ) FROM dd02l
      WHERE ( tabname = @result-node OR tabname = @result-closure ) AND as4local = 'A'
      INTO @DATA(found).
    IF found <> 2.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

  METHOD current.
    DATA(bw) = bw_state( characteristic = characteristic name = name ).
    DATA(tables) = registered_tables( bw-iobjnm ).
    IF tables IS INITIAL.
      refuse( |The hierarchy { name } of { characteristic } has no tables: accept a schema that names it| ).
    ENDIF.
    DATA(bw_tables) = bw_tables( bw-iobjnm ).
    SELECT SINGLE * FROM zzxxmla1_hiedir WHERE hieid = @bw-hieid INTO @DATA(directory).
    IF up_to_date( directory = directory bw = bw ) = abap_false.
      lock( bw-hieid ).
      " another query may have refilled it while this one waited
      SELECT SINGLE * FROM zzxxmla1_hiedir WHERE hieid = @bw-hieid INTO @directory.
      IF up_to_date( directory = directory bw = bw ) = abap_false.
        directory = refill( bw = bw directory = directory tables = tables bw_tables = bw_tables ).
        DATA(refilled) = abap_true.
      ENDIF.
      unlock( bw-hieid ).
    ENDIF.
    result = hierarchy_of( directory = directory tables = tables bw_tables = bw_tables ).
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
    " SVER
    result = xsdbool( directory-sver IS NOT INITIAL
                      AND directory-hiesid = bw-hiesid
                      AND directory-sver = bw-sver ).
  ENDMETHOD.

  METHOD hierarchy_of.
    result = VALUE #( hieid          = directory-hieid
                      characteristic = directory-iobjnm
                      name           = directory-hienm
                      node_table     = tables-node
                      closure_table  = tables-closure
                      sid_table      = bw_tables-sids
                      hiesid         = directory-hiesid
                      sver           = directory-sver
                      root_sid       = directory-root_sid
                      rest_top_sid   = directory-rest_top_sid
                      rest_shown     = xsdbool( directory-norestnodes IS INITIAL ) ).
  ENDMETHOD.

  METHOD values_of.
    DATA(sids) = quote( hierarchy-sid_table ).
    DATA(closure) = quote( hierarchy-closure_table ).
    IF hierarchy-rest_shown = abap_true AND node_sid = hierarchy-rest_top_sid.
      result = VALUE #(
        sql    = |SELECT s."SID" FROM { sids } AS s WHERE NOT EXISTS ( SELECT 1 FROM { closure } AS c | &&
                 |WHERE c."HIESID" = ? AND c."SVER" = ? AND c."ANCESTOR_SID" = ? AND c."SID" = s."SID" )|
        params = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) )
                          ( NEW i( hierarchy-root_sid ) ) ) ).
    ELSEIF hierarchy-rest_shown = abap_true AND node_sid = hierarchy-root_sid.
      result = VALUE #( sql = |SELECT "SID" FROM { sids }| ).
    ELSE.
      result = VALUE #(
        sql    = |SELECT "SID" FROM { closure } WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?|
        params = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ( NEW i( node_sid ) ) ) ).
    ENDIF.
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
    IF directory-hiesid IS NOT INITIAL AND directory-hiesid <> bw-hiesid.
      " BW gave the hierarchy another HIESID: the old copies are no hierarchy of BW any more
      delete_copy( tables = tables hiesid = directory-hiesid ).
    ELSEIF directory-prev_sver IS NOT INITIAL AND directory-prev_sver <> bw-sver.
      " the SVER before the current one: no query reads it any more
      delete_copy( tables = tables hiesid = directory-hiesid sver = directory-prev_sver ).
    ENDIF.
    " rows of this SVER that no directory row names (BW gives a SVER again after its 33 sub-versions)
    delete_copy( tables = tables hiesid = bw-hiesid sver = bw-sver ).
    DATA(key) = VALUE zzxxmla1_cl_sql=>ty_t_param( ( NEW i( bw-hiesid ) ) ( NEW string( bw-sver ) ) ).
    TRY.
        zzxxmla1_cl_sql=>execute( sql    = nodes_sql( tables = tables bw_tables = bw_tables )
                                  params = VALUE #( BASE key ( NEW i( bw-root_sid ) ) ) ).
        zzxxmla1_cl_sql=>execute( sql = end_pos_sql( tables ) params = key ).
        zzxxmla1_cl_sql=>execute( sql = closure_sql( tables ) params = key ).
        check( bw = bw tables = tables bw_tables = bw_tables ).
      CLEANUP.
        ROLLBACK WORK.
    ENDTRY.
    result = VALUE #( BASE directory
                      hieid        = bw-hieid
                      iobjnm       = bw-iobjnm
                      hienm        = bw-hienm
                      hiesid       = bw-hiesid
                      sver         = bw-sver
                      prev_sver    = COND #( WHEN directory-hiesid = bw-hiesid THEN directory-sver )
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
    DATA(key) = VALUE zzxxmla1_cl_sql=>ty_t_param( ( NEW i( hiesid ) ) ).
    DATA(condition) = `"HIESID" = ?`.
    IF sver IS NOT INITIAL.
      APPEND NEW string( sver ) TO key.
      condition = `"HIESID" = ? AND "SVER" = ?`.
    ENDIF.
    zzxxmla1_cl_sql=>execute( sql = |DELETE FROM { quote( tables-node ) } WHERE { condition }| params = key ).
    zzxxmla1_cl_sql=>execute( sql = |DELETE FROM { quote( tables-closure ) } WHERE { condition }| params = key ).
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
    DATA(node) = quote( tables-node ).
    result = |INSERT INTO { quote( tables-closure ) } ( "HIESID", "SVER", "ANCESTOR_SID", "SID" ) | &&
             |SELECT DISTINCT n."HIESID", n."SVER", n."SID", l."SID" FROM { node } AS n | &&
             |INNER JOIN { node } AS l ON l."HIESID" = n."HIESID" AND l."SVER" = n."SVER" AND l."POS" > n."POS" AND l."POS" <= n."END_POS" | &&
             |WHERE n."HIESID" = ? AND n."SVER" = ? AND n."SID" < 0 AND l."SID" >= 0|.
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
