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
"! The copies of BW's hierarchies that the engine reads (docs/next-steps.md, Now: time-independent BW hierarchies,
"! part one): per InfoObject a node table, a closure table and a view of the closure with the not-assigned values,
"! holding all of its hierarchies, as BW's SID structure /BIC/I of the characteristic does, and per copy a row of the
"! directory ZZXXMLA1_HIEDIR (keyed by HIEID, HIESID and SVER).
"! A hierarchy is a name and a version (RSHIEDIR-HIENM, VERSION; blank where the characteristic's hierarchies are not
"! version dependent), served as BW serves it at the key date 9999-12-31, as the views read time-dependent attributes
"! (ZZXXMLA1_CL_BW_VIEW_GEN): where the entire hierarchy is time dependent (RSDCHABAS-HIENMTFL) BW keeps a row of
"! RSHIEDIR, its own HIEID, per slice, and the one valid to 9999-12-31 (c_valid_to) is copied; a version without such
"! a slice is not served. A time-dependent structure (nodes with validity, RSDCHABAS-HIENDTFL) is refused. The
"! authorization check (ZZXXMLA1_CL_BW_AUTH_SQL) copies the slice valid at any date (current with a key date): the
"! slices of a name sit side by side, each its own HIEID, and the copy of a slice is deleted by the next refill of the
"! name once BW has the slice no more.
"! - Node table (ZZXXMLA1H followed by 7 digits): a row per occurrence, the shared subtrees expanded as BW's SID
"!   structure /BIC/I holds them, keyed by HIESID, SVER, PARENT_SID and SID. An inner node has its own negative node SID of
"!   /BIC/K (also each occurrence inside an expanded link, the postable nodes and the virtual root ROOTSID of
"!   RSRHIEDIR_OLAP, the All member, PARENT_SID 0, DEPTH 0, POS 0), a leaf the characteristic's SID (a leaf occurrence
"!   is PARENT_SID and SID). DEPTH is BW's TLEVEL, POS the depth-first number (BW's LISTNO; the values of an interval,
"!   which share its LISTNO, by SID), END_POS the last POS of the subtree. NODE_IOBJ and NODE_NAME are BW's node name
"!   (0HIER_NODE and the text node's name, or the characteristic and the key of a postable node, whose own value
"!   VALUE_SID is its first leaf); of a leaf the characteristic and its key, as the hierarchy lines of BW's analysis
"!   authorizations name a leaf (RSECHIE_STRING), so that the check matches a line on a leaf by name (a compounded
"!   characteristic's key is its compounding's keys at their lengths followed by its own, not observed yet: no
"!   authorization-relevant characteristic of the demos is compounded). levels_sql names a leaf by the view.
"! - Closure table (ZZXXMLA1C, the same digits): per inner node occurrence the distinct SIDs of the leaves below it,
"!   and per leaf its identity row (ANCESTOR_SID = SID), keyed by HIESID, SVER, ANCESTOR_SID and SID, so that every
"!   member, node or leaf, is an ancestor, a fact read is one join (facts to the closure on SID, grouped by
"!   ANCESTOR_SID) and a value reached by two paths counts once. Leaf SIDs are positive, node SIDs negative. The table
"!   holds the assigned values only, whether the hierarchy shows the not-assigned node or not.
"! - Path table (ZZXXMLA1P, the same digits): per occurrence (POS) of a depth from 1 a row per level of its path
"!   (TLEVEL, 1 the roots, down to its own DEPTH), keyed by HIESID, SVER, POS and TLEVEL: the occurrence's own SID,
"!   its parent and depth, and the member on that level (its SID, its POS as LEVEL_POS, NODE_IOBJ, NODE_NAME,
"!   VALUE_SID). Filled by the refill from the node table (the ancestors of an occurrence are the inner nodes whose
"!   subtree, POS to END_POS, holds it), so levels_sql reads a member's path from one table, a fixed number of joins
"!   whatever the depth, and a condition on a member's own SID, depth or parent reaches the table (docs/next-steps.md,
"!   step 9: a self-join per level made the outline's statement long to compile).
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
"! hierarchy of the InfoObject is accepted, never by a query, and deleted by delete_unused when no catalog's schema names
"! one any more (accept and remove of the schema API). A query calls current: one key read each of the directory
"! and RSRHIEDIR_OLAP; when there is no copy of BW's current row (HIESID, SVER, TIMESTMP), it is refilled under the
"! lock ENQUEUE_E_TABLE on ZZXXMLA1_HIEDIR, which another query of the hierarchy waits for. The refill stays in the
"! database (INSERT ... SELECT from /BIC/I and /BIC/K) and refuses, as a fault of the query
"! (ZZXXMLA1_CX_BW_HIERARCHY): a value both an inner node and a leaf, a value twice as an inner node with different
"! subtrees, more than one current row of RSRHIEDIR_OLAP, a time-dependent structure; and a copy whose
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
    CONSTANTS c_path_prefix TYPE string VALUE `ZZXXMLA1P`.
    "! The not-assigned view: its database view and its DDL source.
    CONSTANTS c_rest_view_prefix TYPE string VALUE `ZZXXMLA1R`.
    CONSTANTS c_rest_ddl_prefix TYPE string VALUE `ZZXXMLA1_R`.
    "! The node name of BW's text nodes and of the not-assigned node (/BIC/K-NIOBJNM).
    CONSTANTS c_text_node TYPE rsniobjnm VALUE '0HIER_NODE'.
    "! The name of the not-assigned node (BW's node name of REST_TOP_SID).
    CONSTANTS c_rest_node_name TYPE string VALUE `REST_H`.
    "! The InfoObject BW's MDX gives the not-assigned node, which keys it with its name.
    CONSTANTS c_rest_iobj TYPE string VALUE `1HIER_REST`.
    "! The validity of the slice of a time-dependent hierarchy that is served: BW's key date 9999-12-31.
    CONSTANTS c_valid_to TYPE d VALUE '99991231'.
    "! A copy filled before this time (UTC) has the layout before its leaves were named (NODE_IOBJ, NODE_NAME): it is
    "! refilled once.
    CONSTANTS c_layout_since TYPE timestampl VALUE '20261025000000'.
    "! The language of the node texts, as of the characteristics' texts in the views (ZZXXMLA1_CL_BW_VIEW_GEN).
    CONSTANTS c_language TYPE string VALUE `E`.
    "! The parts of a level's columns of levels_sql.
    CONSTANTS:
      BEGIN OF c_level_part,
        sid     TYPE string VALUE `SID`,
        name    TYPE string VALUE `NAME`,
        pos     TYPE string VALUE `POS`,
        caption TYPE string VALUE `CAPTION`,
        iobj    TYPE string VALUE `IOBJ`,
      END OF c_level_part.
    "! The columns of levels_sql of the member itself, after the levels' columns: its own SID (the key of its deepest
    "! level), its depth (the number of its levels) and its parent's SID (the virtual root for a root).
    CONSTANTS:
      BEGIN OF c_member_column,
        sid    TYPE string VALUE `MEMBER_SID`,
        depth  TYPE string VALUE `MEMBER_DEPTH`,
        parent TYPE string VALUE `MEMBER_PARENT`,
      END OF c_member_column.

    TYPES:
      "! the generated objects of an InfoObject
      BEGIN OF ty_tables,
        node      TYPE tabname,
        closure   TYPE tabname,
        path      TYPE tabname,
        rest_view TYPE tabname,
        rest_ddl  TYPE ddlname,
      END OF ty_tables.
    TYPES:
      "! a characteristic other than the hierarchy's whose values are nodes of it (BW's external characteristics in
      "! hierarchies, RSDHIECHA): its view (ZZXXMLA1_CL_BW_VIEW_GEN) and the view's columns that name and caption these
      "! nodes by their SID (the copy's VALUE_SID, BW's /BIC/K-OSID) as the proposal names and captions the
      "! characteristic's members: COMPOUND_KEY, else KEY_NAME, else the key; its preferred text (the medium, else the
      "! long, else the short one), else KEY_CAPTION. BW's MDX captions them by the short text, but its text
      "! properties are the characteristic's (scripts/bw_hierarchy_test.py compares the text)
      BEGIN OF ty_external,
        iobjnm         TYPE rsiobjnm,
        view           TYPE tabname,
        name_column    TYPE string,
        caption_column TYPE string,
      END OF ty_external,
      ty_t_external TYPE STANDARD TABLE OF ty_external WITH EMPTY KEY.
    TYPES:
      "! a hierarchy's current copy, as a query reads it: its tables, the closure a query reads (the not-assigned view
      "! when the hierarchy shows that node, else the closure table), BW's HIESID and SVER it is a copy of (to bind
      "! in each statement), the SIDs of its All member and of its not-assigned node, whether it shows that node and
      "! its caption (rest_caption), the external characteristics of its nodes that have a view (the others are
      "! named by BW's node name), the depth of its deepest node row and the depths on which a SID repeats (its shape,
      "! read once by refill and kept in its directory row: BW does not change a structure once its SVER is written)
      BEGIN OF ty_hierarchy,
        hieid          TYPE rshieid,
        characteristic TYPE rsiobjnm,
        name           TYPE rshienm,
        version        TYPE rshiedir-version,
        node_table     TYPE tabname,
        closure_table  TYPE tabname,
        path_table     TYPE tabname,
        closure        TYPE tabname,
        hiesid         TYPE i,
        sver           TYPE rsrsver,
        root_sid       TYPE i,
        rest_top_sid   TYPE i,
        rest_shown     TYPE abap_bool,
        rest_caption   TYPE string,
        refilled       TYPE abap_bool,
        externals      TYPE ty_t_external,
        node_depth     TYPE i,
        repeated       TYPE int4_table,
      END OF ty_hierarchy.
    TYPES:
      "! a statement and the values of its parameters
      BEGIN OF ty_statement,
        sql    TYPE string,
        params TYPE zzxxmla1_cl_sql=>ty_t_param,
      END OF ty_statement.

    TYPES ty_r_iobjnm TYPE RANGE OF rsiobjnm.
    TYPES ty_t_iobjnm TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
    TYPES:
      "! the objects delete_unused deleted, or failed to: of an InfoObject of the registry, or of an unregistered
      "! number (characteristic initial)
      BEGIN OF ty_deleted,
        characteristic TYPE rsiobjnm,
        tables         TYPE ty_tables,
        error          TYPE string,
      END OF ty_deleted,
      ty_t_deleted TYPE STANDARD TABLE OF ty_deleted WITH EMPTY KEY.
    TYPES ty_r_hienm TYPE RANGE OF rshienm.
    TYPES:
      "! the outcome of copying a hierarchy (run): the copy, or the error; its counts and the time of current
      BEGIN OF ty_run,
        characteristic TYPE rsiobjnm,
        name           TYPE rshienm,
        version        TYPE rshiedir-version,
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
      "! a hierarchy BW has for a characteristic (offered): its name and version, the name of its Hierarchy in a
      "! schema (hierarchy_name), its text, and whether olap4abap can serve it, else why not
      BEGIN OF ty_offered,
        name      TYPE string,
        version   TYPE string,
        hierarchy TYPE string,
        text      TYPE string,
        supported TYPE abap_bool,
        reason    TYPE string,
      END OF ty_offered,
      ty_t_offered TYPE STANDARD TABLE OF ty_offered WITH EMPTY KEY.

    "! package: the package new tables are created in.
    METHODS constructor
      IMPORTING package TYPE devclass DEFAULT c_default_package.
    "! Creates the node, closure and path tables and the not-assigned view of an InfoObject if it has none (accept of a
    "! schema that names one of its hierarchies); an InfoObject that has them keeps them.
    METHODS create_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! Deletes the not-assigned view, the node, closure and path tables and the copies of an InfoObject, if it has them:
    "! the view reads BW's SID table, so BW cannot delete the InfoObject while it exists (the clinic demo's run).
    METHODS delete_tables
      IMPORTING characteristic TYPE rsiobjnm.
    "! Deletes the objects and copies of every InfoObject that is not among the used ones (the characteristics a BW
    "! hierarchy of a catalog's schema names), so that they do not outlive the schemas (remove and accept of the schema
    "! API): those of the registry ZZXXMLA1_HIETAB and every generated object of the prefixes that the registry does not
    "! name (left by an interrupted create_tables or a registry emptied by an import). An object that cannot be deleted
    "! is an error of its InfoObject (or number) and the others are deleted; the next call tries it again. With test
    "! they are only listed.
    METHODS delete_unused
      IMPORTING used          TYPE ty_t_iobjnm
                test          TYPE abap_bool DEFAULT abap_false
      RETURNING VALUE(result) TYPE ty_t_deleted.
    "! The current copy of a hierarchy of a characteristic (the basic one, RSHIEDIR-IOBJNM) by name and version (its
    "! slice valid at the key date: queries read the one valid to 9999-12-31, the authorization check any), refilled
    "! first if BW's is newer. Raises ZZXXMLA1_CX_BW_HIERARCHY.
    METHODS current
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
                version        TYPE rshiedir-version OPTIONAL
                key_date       TYPE d DEFAULT c_valid_to
      RETURNING VALUE(result)  TYPE ty_hierarchy.
    "! The name of a hierarchy's Hierarchy in a schema: BW's name, followed by _ and the version where it has one
    "! (ZCLDOC_ORG_001).
    CLASS-METHODS hierarchy_name
      IMPORTING name          TYPE csequence
                version       TYPE csequence OPTIONAL
      RETURNING VALUE(result) TYPE string.
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
    "! The column of a level of levels_sql: L01_SID, L01_NAME, L01_POS, L01_CAPTION, L01_IOBJ, ...
    "! @parameter part | c_level_part
    CLASS-METHODS level_column
      IMPORTING !level        TYPE i
                part          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! The members of a copy as a level hierarchy (ZZXXMLA1_CL_MODEL=>member_table of a BW hierarchy), a query to use
    "! as a derived table: a row per member, every occurrence of a node or a leaf (a leaf under two parents twice),
    "! with per level of its path, from the roots down to its own, the member there (level_column): its SID, its name,
    "! its position (POS, BW's order), with a caption column its caption, and its InfoObject (a node's NODE_IOBJ,
    "! 0HIER_NODE of a text node, 1HIER_REST of REST_H, a leaf's the characteristic), which with the name is BW's
    "! key of a node, the levels below it NULL; as the
    "! reference's flattened table of a level hierarchy, but a member on the level of its depth whether it has children
    "! or not (SSAS's parent-child form). A node is named by its node name (NODE_NAME, the key of a postable node) and
    "! captioned by its text (a text node's of RSTHIERNODE, a postable node's value's, an external characteristic's
    "! node named and captioned by its view: ty_external), a leaf named and captioned as the characteristic's member is, by the view's
    "! columns (the initial value too: '' by KEY_NAME). When the hierarchy shows the not-assigned node, REST_H follows the roots, its
    "! values (the closure's rows under it) below it in their names' order. The levels of a member are its rows of
    "! the path table, one per level, turned into columns (grouped by the occurrence); after them the member's own
    "! columns (c_member_column), by which a condition on the member reaches the path table.
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
    "! Creates the objects of each characteristic and copies each of its hierarchies, per name and version the slice
    "! valid to 9999-12-31 (program ZZXXMLA1_HIERARCHY_COPY, the class run for scripts/hierarchy_copy_test.py).
    METHODS run
      IMPORTING characteristics TYPE ty_r_iobjnm
                hierarchies     TYPE ty_r_hienm OPTIONAL
      RETURNING VALUE(result)   TYPE ty_t_run.
    "! The active hierarchies BW has for a characteristic (the basic one, RSHIEDIR-IOBJNM), by name and version, which
    "! the schema builder offers: each with the text of its latest slice in the logon language (medium, else long, else
    "! short, else the name; followed by the version where two versions have the same text), served if it has a slice
    "! valid to 9999-12-31 and its structure is not time dependent (as current asks).
    CLASS-METHODS offered
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_t_offered.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES:
      "! a row of RSHIEDIR as offered reads it: a slice of a hierarchy and its texts in the logon language
      BEGIN OF ty_directory_text,
        hienm   TYPE rshienm,
        version TYPE rshiedir-version,
        dateto  TYPE d,
        txtsh   TYPE string,
        txtmd   TYPE string,
        txtlg   TYPE string,
      END OF ty_directory_text,
      ty_t_directory_text TYPE STANDARD TABLE OF ty_directory_text WITH EMPTY KEY.
    TYPES:
      "! the tables of BW a refill reads
      BEGIN OF ty_bw_tables,
        structure TYPE tabname,   " /BIC/I: SID structure
        node_sids TYPE tabname,   " /BIC/K: node SIDs and names
        sids      TYPE tabname,   " /BIC/S: the characteristic's SIDs
        leaf_name TYPE string,    " the expression of a leaf's key over the SID table (alias s)
      END OF ty_bw_tables.
    TYPES:
      "! BW's current state of a hierarchy, which a copy is compared with
      BEGIN OF ty_bw_state,
        hieid        TYPE rshieid,
        iobjnm       TYPE rsiobjnm,
        hienm        TYPE rshienm,
        version      TYPE rshiedir-version,
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

    "! BW's current state of a hierarchy: its row of RSHIEDIR of the name and version valid at the key date and its
    "! current row of RSRHIEDIR_OLAP (DELETETIMESTMP 0, which must be one).
    METHODS bw_state
      IMPORTING characteristic TYPE rsiobjnm
                name           TYPE rshienm
                version        TYPE rshiedir-version
                key_date       TYPE d
      RETURNING VALUE(result)  TYPE ty_bw_state.
    "! The offered hierarchies of the slices of RSHIEDIR (offered), by name and version; none is served where the
    "! characteristic's structure is time dependent.
    CLASS-METHODS offer
      IMPORTING rows               TYPE ty_t_directory_text
                structure_time_dep TYPE abap_bool
      RETURNING VALUE(result)      TYPE ty_t_offered.
    "! Whether the characteristic's hierarchy structures are time dependent (RSDCHABAS-HIENDTFL: nodes with validity).
    CLASS-METHODS structure_time_dependent
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE abap_bool.
    "! Deletes the copies of the other slices of a hierarchy's name that BW has no more (no active row of RSHIEDIR).
    METHODS delete_old_slices
      IMPORTING bw     TYPE ty_bw_state
                tables TYPE ty_tables.
    METHODS bw_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_bw_tables.
    "! The objects of the registry ZZXXMLA1_HIETAB; initial if the InfoObject has none.
    METHODS registered_tables
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_tables.
    "! Whether the node, closure and path tables and the not-assigned view are active in the DDIC.
    METHODS tables_exist
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE abap_bool.
    "! Whether the directory row is a copy of BW's current state with its shape (a row written before the shape was
    "! kept has depth 0, one filled before c_layout_since has unnamed leaves: each is refilled once).
    CLASS-METHODS up_to_date
      IMPORTING directory     TYPE ty_directory
                bw            TYPE ty_bw_state
      RETURNING VALUE(result) TYPE abap_bool.
    "! The copies of a hierarchy that BW keeps no version of (its HIESID, SVER and TIMESTMP).
    CLASS-METHODS stale_copies
      IMPORTING copies        TYPE ty_t_directory
                versions      TYPE ty_t_version
      RETURNING VALUE(result) TYPE ty_t_directory.
    "! The external characteristics of a copy's nodes that have a view (ty_external), of the InfoObjects its
    "! directory row names (NODE_IOBJS).
    CLASS-METHODS externals
      IMPORTING node_iobjs    TYPE csequence
      RETURNING VALUE(result) TYPE ty_t_external.
    "! The shape of a new copy, for its directory row: DEPTH the depth of its deepest node row, REPEATED the depths
    "! (1: the roots) on which a SID occurs more than once and NODE_IOBJS the InfoObjects of its nodes other than
    "! text nodes and the characteristic (BW's external characteristics), each separated by a space.
    CLASS-METHODS shape
      IMPORTING tables         TYPE ty_tables
                hiesid         TYPE i
                sver           TYPE rsrsver
                characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE ty_directory.
    "! The caption of the not-assigned node as BW's MDX gives it: Not Assigned, the characteristic's text (long, else
    "! short, else its name) in c_language and (s).
    CLASS-METHODS rest_caption
      IMPORTING characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE string.
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
    "! Whether the generated tables have the columns of node_columns, closure_columns and path_columns, in their order.
    METHODS current_columns
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE abap_bool.
    METHODS delete_table
      IMPORTING name TYPE tabname.
    "! Deletes the not-assigned view (first, it reads the closure table) and the node, closure and path tables.
    METHODS delete_objects
      IMPORTING tables TYPE ty_tables.
    "! The statements of a refill (the parameters in the order of their ?; HIESID and SVER are a copy's key).
    "! nodes: HIESID, SVER, ROOTSID
    CLASS-METHODS nodes_sql
      IMPORTING tables         TYPE ty_tables
                bw_tables      TYPE ty_bw_tables
                characteristic TYPE rsiobjnm
      RETURNING VALUE(result)  TYPE string.
    "! The expression of a leaf's key over the SID table (alias s): the key field, of a compounded characteristic
    "! the keys of its compounding, each at its length, followed by its own.
    CLASS-METHODS leaf_name
      IMPORTING metadata      TYPE zzxxmla1_cl_bw_view_gen=>ty_metadata
      RETURNING VALUE(result) TYPE string.
    "! subtree ends of the inner nodes: HIESID, SVER
    CLASS-METHODS end_pos_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! closure, the inner nodes' rows and the leaves' identity rows: HIESID, SVER, HIESID, SVER
    CLASS-METHODS closure_sql
      IMPORTING tables        TYPE ty_tables
      RETURNING VALUE(result) TYPE string.
    "! paths, a row per occurrence and level of its path: HIESID, SVER
    CLASS-METHODS path_sql
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
    "! the columns of the node, closure and path tables
    CLASS-METHODS node_columns
      RETURNING VALUE(result) TYPE ty_t_column.
    CLASS-METHODS closure_columns
      RETURNING VALUE(result) TYPE ty_t_column.
    CLASS-METHODS path_columns
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
    "! the numbers of the generated objects in the DDIC (tables, views and DDL sources of the prefixes followed by 7
    "! digits), ascending
    METHODS generated_numbers
      RETURNING VALUE(result) TYPE int4_table.
    "! the number of a generated object's name after its prefix; 0 if it is not one
    CLASS-METHODS number_of
      IMPORTING !name         TYPE csequence
                prefix        TYPE string
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
    SELECT iobjnm, hienm, version FROM rshiedir
      WHERE iobjnm IN @characteristics AND hienm IN @hierarchies AND objvers = 'A' AND dateto = @c_valid_to
      ORDER BY iobjnm ASCENDING, hienm ASCENDING, version ASCENDING
      INTO TABLE @DATA(rows).
    LOOP AT rows INTO DATA(row).
      DATA(line) = VALUE ty_run( characteristic = row-iobjnm name = row-hienm version = row-version ).
      TRY.
          line-tables = create_tables( row-iobjnm ).
          GET RUN TIME FIELD DATA(started).
          line-hierarchy = current( characteristic = row-iobjnm name = row-hienm version = row-version ).
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
    DATA rows TYPE ty_t_directory_text.
    SELECT d~hienm, d~version, d~dateto, t~txtsh, t~txtmd, t~txtlg
      FROM rshiedir AS d
      LEFT OUTER JOIN rshiedirt AS t ON t~hieid = d~hieid AND t~objvers = d~objvers AND t~langu = @sy-langu
      WHERE d~iobjnm = @characteristic AND d~objvers = 'A'
      INTO CORRESPONDING FIELDS OF TABLE @rows.
    result = offer( rows = rows structure_time_dep = structure_time_dependent( characteristic ) ).
  ENDMETHOD.

  METHOD offer.
    DATA(sorted) = rows.
    SORT sorted BY hienm ASCENDING version ASCENDING dateto DESCENDING.
    LOOP AT sorted INTO DATA(row) GROUP BY ( hienm = row-hienm version = row-version ) INTO DATA(group).
      DATA(entry) = VALUE ty_offered( name      = condense( group-hienm )
                                      version   = condense( group-version )
                                      hierarchy = hierarchy_name( name = group-hienm version = group-version ) ).
      LOOP AT GROUP group INTO DATA(member).
        " the latest slice first: its text, also of a version without a slice valid to 9999-12-31
        IF entry-text IS INITIAL.
          entry-text = condense( COND string( WHEN member-txtmd IS NOT INITIAL THEN member-txtmd
                                              WHEN member-txtlg IS NOT INITIAL THEN member-txtlg
                                              ELSE member-txtsh ) ).
        ENDIF.
        IF member-dateto = c_valid_to.
          entry-supported = abap_true.
        ENDIF.
      ENDLOOP.
      IF structure_time_dep = abap_true.
        entry-supported = abap_false.
        entry-reason = `its structure is time dependent, which olap4abap does not support yet`.
      ELSEIF entry-supported = abap_false.
        entry-reason = |it has no slice valid to { c_valid_to DATE = ISO }|.
      ENDIF.
      IF entry-text IS INITIAL.
        entry-text = entry-name.
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.
    " versions of the same text are told apart by the version
    DATA(texts) = result.
    LOOP AT result ASSIGNING FIELD-SYMBOL(<entry>) WHERE version IS NOT INITIAL.
      DATA(same) = REDUCE i( INIT n = 0 FOR t IN texts WHERE ( text = <entry>-text ) NEXT n = n + 1 ).
      IF same > 1.
        <entry>-text = |{ <entry>-text } ({ <entry>-version })|.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD structure_time_dependent.
    SELECT SINGLE hiendtfl FROM rsdchabas WHERE chabasnm = @characteristic AND objvers = 'A' INTO @DATA(flag).
    result = xsdbool( sy-subrc = 0 AND flag IS NOT INITIAL ).
  ENDMETHOD.

  METHOD hierarchy_name.
    result = condense( CONV string( name ) ).
    DATA(suffix) = condense( CONV string( version ) ).
    IF suffix IS NOT INITIAL.
      result = |{ result }_{ suffix }|.
    ENDIF.
  ENDMETHOD.

  METHOD create_tables.
    result = registered_tables( characteristic ).
    IF result IS NOT INITIAL AND tables_exist( result ) = abap_true AND current_columns( result ) = abap_true.
      RETURN.
    ENDIF.
    IF result IS NOT INITIAL.
      " objects of an older layout, or some of them missing: the copies are BW's data, so the objects are made again
      " under their names (the view first, it reads the closure table) and the next query refills them
      result = tables_of_number( number_of( name = result-node prefix = c_node_prefix ) ).
      delete_objects( result ).
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
    create_table( name        = result-path
                  description = |BW hierarchy paths { characteristic }|
                  columns     = path_columns( ) ).
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
    delete_objects( tables ).
    DELETE FROM zzxxmla1_hiedir WHERE iobjnm = @characteristic.
    DELETE FROM zzxxmla1_hietab WHERE iobjnm = @characteristic.
    COMMIT WORK.
  ENDMETHOD.

  METHOD delete_unused.
    SELECT iobjnm, node_table FROM zzxxmla1_hietab ORDER BY iobjnm ASCENDING INTO TABLE @DATA(registered).
    DATA kept TYPE int4_table.
    LOOP AT registered INTO DATA(row).
      DATA(number) = number_of( name = row-node_table prefix = c_node_prefix ).
      IF line_exists( used[ table_line = row-iobjnm ] ).
        APPEND number TO kept.
        CONTINUE.
      ENDIF.
      DATA(entry) = VALUE ty_deleted( characteristic = row-iobjnm tables = registered_tables( row-iobjnm ) ).
      IF test = abap_true.
        " listed with its InfoObject, not again below as an unregistered number
        APPEND number TO kept.
        APPEND entry TO result.
        CONTINUE.
      ENDIF.
      TRY.
          delete_tables( row-iobjnm ).
        CATCH zzxxmla1_cx_bw_hierarchy INTO DATA(error).
          entry-error = error->get_text( ).
          " the registry row stays, so that the next call tries again
          APPEND number TO kept.
      ENDTRY.
      APPEND entry TO result.
    ENDLOOP.
    " the objects no registry row names (the deleted ones are gone from the DDIC by now)
    LOOP AT generated_numbers( ) INTO number.
      IF line_exists( kept[ table_line = number ] ).
        CONTINUE.
      ENDIF.
      CLEAR entry.
      entry-tables = tables_of_number( number ).
      IF test = abap_false.
        TRY.
            delete_objects( entry-tables ).
          CATCH zzxxmla1_cx_bw_hierarchy INTO error.
            entry-error = error->get_text( ).
        ENDTRY.
      ENDIF.
      APPEND entry TO result.
    ENDLOOP.
    IF test = abap_true.
      RETURN.
    ENDIF.
    " the directory rows of the InfoObjects whose objects are gone
    DATA left TYPE ty_r_iobjnm.
    LOOP AT registered INTO row.
      IF NOT line_exists( result[ characteristic = row-iobjnm error = `` ] ).
        APPEND VALUE #( sign = 'I' option = 'EQ' low = row-iobjnm ) TO left.
      ENDIF.
    ENDLOOP.
    IF left IS INITIAL.
      DELETE FROM zzxxmla1_hiedir.
    ELSE.
      DELETE FROM zzxxmla1_hiedir WHERE iobjnm NOT IN @left.
    ENDIF.
    COMMIT WORK.
  ENDMETHOD.

  METHOD delete_objects.
    " the view first, it reads the closure table
    delete_rest_view( tables ).
    delete_table( tables-node ).
    delete_table( tables-closure ).
    delete_table( tables-path ).
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
    DATA(expected_path) = VALUE string_table( FOR q IN path_columns( ) ( CONV string( q-name ) ) ).
    SELECT fieldname FROM dd03l WHERE tabname = @tables-path AND as4local = 'A'
      ORDER BY position ASCENDING INTO TABLE @DATA(path_fields).
    DATA(actual_path) = VALUE string_table( FOR h IN path_fields ( CONV string( h-fieldname ) ) ).
    result = xsdbool( actual = expected AND actual_closure = expected_closure AND actual_path = expected_path ).
  ENDMETHOD.

  METHOD delete_table.
    " RS_DD_DELETE_OBJ asks before it deletes a table with data (dialog_needed with no_ask): emptied first
    SELECT SINGLE tabname FROM dd02l WHERE tabname = @name AND as4local = 'A' INTO @DATA(active) ##NEEDED.
    IF sy-subrc = 0.
      TRY.
          zzxxmla1_cl_sql=>execute( |DELETE FROM { quote( name ) }| ).
          COMMIT WORK.
        CATCH zzxxmla1_cx_sql INTO DATA(error).
          refuse( |Table { name } cannot be emptied: { error->error_message }| ).
      ENDTRY.
    ENDIF.
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
      RETURN.
    ENDIF.
    " the path table has the digits of the node table (not in the registry, which predates it)
    result-path = table_name( prefix = c_path_prefix number = number_of( name = result-node prefix = c_node_prefix ) ).
  ENDMETHOD.

  METHOD tables_exist.
    " all four must be active in the DDIC
    SELECT COUNT( * ) FROM dd02l
      WHERE ( tabname = @tables-node OR tabname = @tables-closure OR tabname = @tables-path
              OR tabname = @tables-rest_view ) AND as4local = 'A'
      INTO @DATA(found).
    result = xsdbool( found = 4 ).
  ENDMETHOD.

  METHOD current.
    DATA(bw) = bw_state( characteristic = characteristic name = name version = version key_date = key_date ).
    DATA(tables) = registered_tables( bw-iobjnm ).
    IF tables IS INITIAL OR tables_exist( tables ) = abap_false.
      refuse( |The hierarchy { hierarchy_name( name = name version = version ) } of { characteristic } has no | &&
              |tables: accept a schema that names it or run ZZXXMLA1_HIERARCHY_COPY| ).
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
    result-version = bw-version.
    result-refilled = refilled.
    result-externals = externals( directory-node_iobjs ).
    IF result-rest_shown = abap_true.
      result-rest_caption = rest_caption( characteristic ).
    ENDIF.
  ENDMETHOD.

  METHOD rest_caption.
    SELECT SINGLE txtsh, txtlg FROM rsdiobjt
      WHERE iobjnm = @characteristic AND langu = @c_language AND objvers = 'A'
      INTO @DATA(text).
    DATA(caption) = COND string( WHEN text-txtlg IS NOT INITIAL THEN text-txtlg
                                 WHEN text-txtsh IS NOT INITIAL THEN text-txtsh
                                 ELSE characteristic ).
    result = |Not Assigned { caption } (s)|.
  ENDMETHOD.

  METHOD externals.
    SPLIT condense( node_iobjs ) AT ` ` INTO TABLE DATA(names).
    DELETE names WHERE table_line IS INITIAL.
    IF names IS INITIAL.
      RETURN.
    ENDIF.
    DATA(views) = NEW zzxxmla1_cl_bw_view_gen( ).
    LOOP AT names INTO DATA(name_of_iobj).
      DATA(iobjnm) = CONV rsiobjnm( name_of_iobj ).
      DATA(layout) = views->layout( iobjnm ).
      DATA(view) = views->existing_view( layout-tables-basic ).
      IF view IS INITIAL.
        CONTINUE.
      ENDIF.
      DATA(columns) = layout-columns.
      DATA(name) = COND string(
        WHEN line_exists( columns[ name = zzxxmla1_cl_bw_view_gen=>c_compound_key ] )
        THEN zzxxmla1_cl_bw_view_gen=>c_compound_key
        WHEN line_exists( columns[ name = zzxxmla1_cl_bw_view_gen=>c_key_name ] )
        THEN zzxxmla1_cl_bw_view_gen=>c_key_name
        ELSE VALUE #( columns[ iobjnm = layout-tables-basic text = abap_false ]-name OPTIONAL ) ).
      DATA(caption) = VALUE string( columns[ iobjnm = layout-tables-basic preferred = abap_true ]-name OPTIONAL ).
      IF caption IS INITIAL AND line_exists( columns[ name = zzxxmla1_cl_bw_view_gen=>c_key_caption ] ).
        caption = zzxxmla1_cl_bw_view_gen=>c_key_caption.
      ENDIF.
      IF name IS NOT INITIAL.
        APPEND VALUE #( iobjnm         = iobjnm
                        view           = view
                        name_column    = name
                        caption_column = COND #( WHEN caption IS NOT INITIAL THEN caption ELSE name ) ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD bw_state.
    DATA(shown) = hierarchy_name( name = name version = version ).
    SELECT hieid, iobjnm, hienm, version, datefrom, dateto, norestnodes FROM rshiedir
      WHERE iobjnm = @characteristic AND hienm = @name AND version = @version AND objvers = 'A'
      ORDER BY dateto DESCENDING
      INTO TABLE @DATA(rows).
    IF rows IS INITIAL.
      refuse( |BW has no active hierarchy { shown } of { characteristic }| ).
    ENDIF.
    IF structure_time_dependent( characteristic ) = abap_true.
      refuse( |The hierarchy { shown } of { characteristic } has a time-dependent structure, which olap4abap does | &&
              |not support yet| ).
    ENDIF.
    DATA(found) = abap_false.
    LOOP AT rows INTO DATA(row) WHERE datefrom <= key_date AND dateto >= key_date.
      found = abap_true.
      EXIT.
    ENDLOOP.
    IF found = abap_false.
      refuse( |The hierarchy { shown } of { characteristic } has no slice valid | &&
              COND string( WHEN key_date = c_valid_to THEN |to { c_valid_to DATE = ISO }|
                           ELSE |at { key_date DATE = ISO }| ) ).
    ENDIF.
    result = VALUE #( hieid = row-hieid iobjnm = row-iobjnm hienm = row-hienm version = row-version
                      norestnodes = row-norestnodes ).
    SELECT hiesid, sver, timestmp, rootsid, resttopsid FROM rsrhiedir_olap
      WHERE hieid = @row-hieid AND objvers = 'A' AND deletetimestmp = 0
      INTO TABLE @DATA(olap).
    IF lines( olap ) <> 1.
      refuse( |The hierarchy { shown } of { characteristic } has { lines( olap ) } current rows in RSRHIEDIR_OLAP| &&
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
    DATA(metadata) = NEW zzxxmla1_cl_bw_view_gen( )->metadata( characteristic ).
    result = VALUE #( structure = structure
                      node_sids = node_sids
                      sids      = metadata-tables-sids
                      leaf_name = leaf_name( metadata ) ).
    IF result-sids IS INITIAL OR result-leaf_name IS INITIAL.
      refuse( |BW has no SID table of { characteristic }| ).
    ENDIF.
  ENDMETHOD.

  METHOD leaf_name.
    DATA(parts) = VALUE string_table( ).
    LOOP AT metadata-compounding INTO DATA(compounding).
      DATA(length) = VALUE i( metadata-sid_columns[ field = compounding-field ]-length OPTIONAL ).
      APPEND |RPAD( s.{ quote( compounding-field ) }, { length } )| TO parts.
    ENDLOOP.
    IF metadata-tables-key_field IS NOT INITIAL.
      APPEND |s.{ quote( metadata-tables-key_field ) }| TO parts.
      result = concat_lines_of( table = parts sep = ` || ` ).
    ENDIF.
  ENDMETHOD.

  METHOD up_to_date.
    " BW does not change a structure once its SVER is written: a change, also of the not-assigned setting, is a new
    " SVER; the same SVER of another TIMESTMP is BW's SVER given again
    result = xsdbool( directory-sver IS NOT INITIAL
                      AND directory-hiesid = bw-hiesid
                      AND directory-sver = bw-sver
                      AND directory-timestmp = bw-timestmp
                      AND directory-depth > 0
                      AND directory-filled_at >= c_layout_since ).
  ENDMETHOD.

  METHOD delete_old_slices.
    " a slice of an entirely time-dependent hierarchy is a HIEID of its own: the check reads the copy of any slice BW
    " has, so a copy is read no more once BW deletes its slice
    SELECT * FROM zzxxmla1_hiedir
      WHERE iobjnm = @bw-iobjnm AND hienm = @bw-hienm AND hieid <> @bw-hieid
        AND hieid NOT IN ( SELECT hieid FROM rshiedir
                             WHERE iobjnm = @bw-iobjnm AND hienm = @bw-hienm AND objvers = 'A' )
      INTO TABLE @DATA(old).
    LOOP AT old INTO DATA(copy).
      delete_copy( tables = tables hiesid = copy-hiesid sver = copy-sver ).
      DELETE FROM zzxxmla1_hiedir WHERE hieid = @copy-hieid AND hiesid = @copy-hiesid AND sver = @copy-sver.
    ENDLOOP.
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
                      path_table     = tables-path
                      closure        = COND #( WHEN shown = abap_true THEN tables-rest_view ELSE tables-closure )
                      hiesid         = directory-hiesid
                      sver           = directory-sver
                      root_sid       = directory-root_sid
                      rest_top_sid   = directory-rest_top_sid
                      rest_shown     = shown
                      node_depth     = directory-depth ).
    SPLIT condense( directory-repeated ) AT ` ` INTO TABLE DATA(repeated).
    LOOP AT repeated INTO DATA(depth) WHERE table_line IS NOT INITIAL.
      APPEND CONV i( depth ) TO result-repeated.
    ENDLOOP.
  ENDMETHOD.

  METHOD shape.
    DATA(key) = VALUE zzxxmla1_cl_sql=>ty_t_param( ( NEW i( hiesid ) ) ( NEW string( sver ) ) ).
    DATA(node) = quote( tables-node ).
    DATA(rows) = zzxxmla1_cl_sql=>query(
      sql     = |SELECT COALESCE( MAX( "DEPTH" ), 0 ) FROM { node } WHERE "HIESID" = ? AND "SVER" = ?|
      columns = 1
      params  = key ).
    result-depth = rows[ 1 ][ 1 ].
    rows = zzxxmla1_cl_sql=>query(
      sql     = |SELECT DISTINCT "DEPTH" FROM { node } | &&
                |WHERE "HIESID" = ? AND "SVER" = ? AND "DEPTH" > 0 GROUP BY "DEPTH", "SID" HAVING COUNT( * ) > 1 | &&
                |ORDER BY "DEPTH"|
      columns = 1
      params  = key ).
    result-repeated = concat_lines_of(
      table = VALUE string_table( FOR row IN rows ( condense( CONV string( row[ 1 ] ) ) ) ) sep = ` ` ).
    rows = zzxxmla1_cl_sql=>query(
      sql     = |SELECT DISTINCT "NODE_IOBJ" FROM { node } | &&
                |WHERE "HIESID" = ? AND "SVER" = ? AND "SID" < 0 AND "NODE_IOBJ" NOT IN ( ?, ?, '' ) | &&
                |ORDER BY "NODE_IOBJ"|
      columns = 1
      params  = VALUE #( BASE key ( NEW string( c_text_node ) ) ( NEW string( characteristic ) ) ) ).
    result-node_iobjs = concat_lines_of(
      table = VALUE string_table( FOR row IN rows ( condense( CONV string( row[ 1 ] ) ) ) ) sep = ` ` ).
  ENDMETHOD.

  METHOD values_of.
    result = VALUE #(
      sql    = |SELECT "SID" FROM { quote( hierarchy-closure ) } WHERE "HIESID" = ? AND "SVER" = ? AND "ANCESTOR_SID" = ?|
      params = VALUE #( ( NEW i( hierarchy-hiesid ) ) ( NEW string( hierarchy-sver ) ) ( NEW i( node_sid ) ) ) ).
  ENDMETHOD.

  METHOD depth.
    result = hierarchy-node_depth.
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
    result = hierarchy-repeated.
  ENDMETHOD.

  METHOD level_column.
    result = |L{ level WIDTH = 2 ALIGN = RIGHT PAD = `0` }_{ part }|.
  ENDMETHOD.

  METHOD levels_sql.
    " the path table's rows of the occurrences of depth 1 to depth, a row per level: the member there named and
    " captioned (e), then a column per level and part, grouped by the occurrence (each level one row of it); the joins
    " are the same whatever the depth. A node of an external characteristic is named and captioned by its view (BW's
    " node name where the view has no row of its SID), a text node captioned by its text of RSTHIERNODE in c_language
    " (medium, else long, else short, else its name), a postable node by its value's caption, a leaf named and
    " captioned as the characteristic's member, by the view's columns (SID 0 too)
    DATA(sver) = zzxxmla1_cl_sql=>literal( CONV string( hierarchy-sver ) ).
    DATA(joins) = |LEFT OUTER JOIN { quote( value_table ) } AS v ON v.{ quote( sid_column ) } = p."SID" AND p."SID" >= 0|.
    DATA(node_names) = ``.
    DATA(node_captions) = ``.
    IF caption_column IS NOT INITIAL.
      joins = |{ joins } LEFT OUTER JOIN "RSTHIERNODE" AS t ON t."LANGU" = { zzxxmla1_cl_sql=>literal( c_language ) } | &&
              |AND t."HIEID" = { zzxxmla1_cl_sql=>literal( CONV string( hierarchy-hieid ) ) } AND t."OBJVERS" = 'A' | &&
              |AND p."NODE_IOBJ" = { zzxxmla1_cl_sql=>literal( CONV string( c_text_node ) ) } | &&
              |AND t."NODENAME" = p."NODE_NAME"| &&
              | LEFT OUTER JOIN { quote( value_table ) } AS pv | &&
              |ON p."NODE_IOBJ" = { zzxxmla1_cl_sql=>literal( CONV string( hierarchy-characteristic ) ) } | &&
              |AND pv.{ quote( sid_column ) } = p."VALUE_SID" AND p."SID" < 0|.
      node_captions = |TO_NVARCHAR( pv.{ quote( caption_column ) } ), |.
    ENDIF.
    LOOP AT hierarchy-externals INTO DATA(external).
      DATA(alias) = |x{ sy-tabix }|.
      joins = |{ joins } LEFT OUTER JOIN { quote( external-view ) } AS { alias } | &&
              |ON p."NODE_IOBJ" = { zzxxmla1_cl_sql=>literal( CONV string( external-iobjnm ) ) } | &&
              |AND { alias }."SID" = p."VALUE_SID"|.
      node_names = |{ node_names }TO_NVARCHAR( { alias }.{ quote( external-name_column ) } ), |.
      node_captions = |{ node_captions }TO_NVARCHAR( { alias }.{ quote( external-caption_column ) } ), |.
    ENDLOOP.
    DATA(node_name) = COND string( WHEN node_names IS INITIAL THEN |TO_NVARCHAR( p."NODE_NAME" )|
                                   ELSE |COALESCE( { node_names }TO_NVARCHAR( p."NODE_NAME" ) )| ).
    DATA(value_name) = |COALESCE( TO_NVARCHAR( v.{ quote( name_column ) } ), TO_NVARCHAR( p."SID" ) )|.
    DATA(value_iobj) = zzxxmla1_cl_sql=>literal( CONV string( hierarchy-characteristic ) ).
    DATA(member) = |p."POS", p."TLEVEL", p."DEPTH", p."OWN_SID", p."PARENT_SID", p."SID", p."LEVEL_POS", | &&
                   |CASE WHEN p."SID" < 0 THEN { node_name } ELSE { value_name } END AS "NAME", | &&
                   |CASE WHEN p."SID" < 0 THEN TO_NVARCHAR( p."NODE_IOBJ" ) ELSE { value_iobj } END AS "IOBJ"|.
    IF caption_column IS NOT INITIAL.
      member = |{ member }, CASE WHEN p."SID" < 0 THEN COALESCE( { node_captions }NULLIF( t."TXTMD", '' ), | &&
               |NULLIF( t."TXTLG", '' ), NULLIF( t."TXTSH", '' ), TO_NVARCHAR( p."NODE_NAME" ) ) | &&
               |ELSE COALESCE( TO_NVARCHAR( v.{ quote( caption_column ) } ), { value_name } ) END AS "CAPTION"|.
    ENDIF.
    DATA(columns) = VALUE string_table( ).
    DATA(parts) = VALUE string_table( ( c_level_part-sid ) ( c_level_part-name ) ( c_level_part-pos ) ).
    IF caption_column IS NOT INITIAL.
      APPEND c_level_part-caption TO parts.
    ENDIF.
    APPEND c_level_part-iobj TO parts.
    DO depth TIMES.
      DATA(level) = sy-index.
      LOOP AT parts INTO DATA(part).
        DATA(source) = COND string( WHEN part = c_level_part-sid THEN `"SID"`
                                    WHEN part = c_level_part-pos THEN `"LEVEL_POS"`
                                    ELSE quote( part ) ).
        APPEND |MAX( CASE WHEN e."TLEVEL" = { level } THEN e.{ source } END ) | &&
               |AS { quote( level_column( level = level part = part ) ) }| TO columns.
      ENDLOOP.
    ENDDO.
    APPEND |e."OWN_SID" AS { quote( c_member_column-sid ) }| TO columns.
    APPEND |e."DEPTH" AS { quote( c_member_column-depth ) }| TO columns.
    APPEND |e."PARENT_SID" AS { quote( c_member_column-parent ) }| TO columns.
    result = |SELECT { concat_lines_of( table = columns sep = `, ` ) } | &&
             |FROM ( SELECT { member } FROM { quote( hierarchy-path_table ) } AS p { joins } | &&
             |WHERE p."HIESID" = { hierarchy-hiesid } AND p."SVER" = { sver } AND p."DEPTH" BETWEEN 1 AND { depth } ) AS e | &&
             |GROUP BY e."POS", e."DEPTH", e."OWN_SID", e."PARENT_SID"|.
    IF hierarchy-rest_shown = abap_false.
      RETURN.
    ENDIF.

    " REST_H after the roots (a root: the virtual root its parent), its values below it: the closure's rows under it
    DATA(empty) = |CAST( NULL AS INTEGER ), CAST( NULL AS NVARCHAR( 1 ) ), CAST( NULL AS INTEGER )| &&
                  COND string( WHEN caption_column IS NOT INITIAL THEN |, CAST( NULL AS NVARCHAR( 1 ) )| ) &&
                  |, CAST( NULL AS NVARCHAR( 1 ) )|.
    DATA(below) = ``.
    DO depth - 2 TIMES.
      below = |{ below }, { empty }|.
    ENDDO.
    DATA(rest_caption) = COND string( WHEN hierarchy-rest_caption IS NOT INITIAL THEN hierarchy-rest_caption
                                      ELSE c_rest_node_name ).
    DATA(rest) = |{ hierarchy-rest_top_sid }, '{ c_rest_node_name }', { c_rest_listno }| &&
                 COND string( WHEN caption_column IS NOT INITIAL
                              THEN |, { zzxxmla1_cl_sql=>literal( rest_caption ) }| ) &&
                 |, '{ c_rest_iobj }'|.
    value_name = |COALESCE( TO_NVARCHAR( v.{ quote( name_column ) } ), TO_NVARCHAR( r."SID" ) )|.
    DATA(value) = |r."SID", { value_name }, { c_rest_listno } + ROW_NUMBER( ) OVER ( ORDER BY { value_name } )| &&
                  COND string( WHEN caption_column IS NOT INITIAL
                               THEN |, COALESCE( TO_NVARCHAR( v.{ quote( caption_column ) } ), { value_name } )| ) &&
                  |, { value_iobj }|.
    result = |{ result } UNION ALL SELECT { rest }, { empty }{ below }, | &&
             |{ hierarchy-rest_top_sid }, 1, { hierarchy-root_sid } FROM DUMMY| &&
             | UNION ALL SELECT { rest }, { value }{ below }, r."SID", 2, { hierarchy-rest_top_sid } | &&
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
        delete_old_slices( bw = bw tables = tables ).
        " rows of this SVER that no directory row names (a refill that did not finish)
        delete_copy( tables = tables hiesid = bw-hiesid sver = bw-sver ).
        zzxxmla1_cl_sql=>execute( sql    = nodes_sql( tables = tables bw_tables = bw_tables characteristic = bw-iobjnm )
                                  params = VALUE #( BASE key ( NEW i( bw-root_sid ) ) ) ).
        zzxxmla1_cl_sql=>execute( sql = end_pos_sql( tables ) params = key ).
        zzxxmla1_cl_sql=>execute( sql = closure_sql( tables ) params = VALUE #( BASE key ( LINES OF key ) ) ).
        zzxxmla1_cl_sql=>execute( sql = path_sql( tables ) params = key ).
        check( bw = bw tables = tables bw_tables = bw_tables ).
        DATA(shape) = shape( tables = tables hiesid = bw-hiesid sver = bw-sver characteristic = bw-iobjnm ).
      CLEANUP.
        ROLLBACK WORK.
    ENDTRY.
    result = VALUE #( BASE shape
                      hiesid       = bw-hiesid
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
    zzxxmla1_cl_sql=>execute( sql = |DELETE FROM { quote( tables-path ) } WHERE "HIESID" = ? AND "SVER" = ?| params = key ).
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
    " correction rows (LISTNO 0) are left out; a node named by /BIC/K, a leaf (SID from 0) by the characteristic and
    " its key
    DATA(listno) = |ROW_NUMBER( ) OVER ( ORDER BY i."LISTNO", i."SUCC" ) - 1|.
    DATA(leaf) = |i."SUCC" >= 0|.
    result = |INSERT INTO { quote( tables-node ) } ( "HIESID", "SVER", "PARENT_SID", "SID", "DEPTH", "POS", "END_POS", | &&
             |"NODE_IOBJ", "NODE_NAME", "VALUE_SID" ) | &&
             |SELECT i."HIESID", i."SVER", CASE WHEN i."LISTNO" = 0 THEN 0 ELSE i."PRED" END, i."SUCC", | &&
             |CAST( i."TLEVEL" AS INTEGER ), { listno }, { listno }, | &&
             |COALESCE( k."NIOBJNM", CASE WHEN { leaf } THEN { zzxxmla1_cl_sql=>literal( CONV string( characteristic ) ) } | &&
             |END, '' ), COALESCE( k."NODENAME", CASE WHEN { leaf } THEN { bw_tables-leaf_name } END, '' ), | &&
             |COALESCE( k."OSID", 0 ) | &&
             |FROM { quote( bw_tables-structure ) } AS i | &&
             |LEFT OUTER JOIN { quote( bw_tables-node_sids ) } AS k ON k."HIESID" = i."HIESID" AND k."SID" = i."SUCC" | &&
             |LEFT OUTER JOIN { quote( bw_tables-sids ) } AS s ON s."SID" = i."SUCC" AND { leaf } | &&
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

  METHOD path_sql.
    " the levels of an occurrence: itself and the inner nodes whose subtree holds it (a leaf's END_POS is its POS),
    " each on the level of its depth; the virtual root (DEPTH 0) is on none
    DATA(node) = quote( tables-node ).
    result = |INSERT INTO { quote( tables-path ) } ( "HIESID", "SVER", "POS", "TLEVEL", "DEPTH", "OWN_SID", | &&
             |"PARENT_SID", "SID", "LEVEL_POS", "NODE_IOBJ", "NODE_NAME", "VALUE_SID" ) | &&
             |SELECT n."HIESID", n."SVER", n."POS", a."DEPTH", n."DEPTH", n."SID", n."PARENT_SID", a."SID", a."POS", | &&
             |a."NODE_IOBJ", a."NODE_NAME", a."VALUE_SID" FROM { node } AS n | &&
             |INNER JOIN { node } AS a ON a."HIESID" = n."HIESID" AND a."SVER" = n."SVER" AND a."DEPTH" >= 1 | &&
             |AND a."POS" <= n."POS" AND a."END_POS" >= n."POS" | &&
             |WHERE n."HIESID" = ? AND n."SVER" = ? AND n."DEPTH" >= 1|.
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

  METHOD path_columns.
    result = VALUE #( ( name = 'HIESID'     rollname = 'RSRHIESID'           key = abap_true )
                      ( name = 'SVER'       rollname = 'RSRSVER'             key = abap_true )
                      ( name = 'POS'        rollname = 'INT4'                key = abap_true )
                      ( name = 'TLEVEL'     rollname = 'INT4'                key = abap_true )
                      ( name = 'DEPTH'      rollname = 'INT4' )
                      ( name = 'OWN_SID'    rollname = 'RSSID' )
                      ( name = 'PARENT_SID' rollname = 'RSSID' )
                      ( name = 'SID'        rollname = 'RSSID' )
                      ( name = 'LEVEL_POS'  rollname = 'INT4' )
                      ( name = 'NODE_IOBJ'  rollname = 'RSNIOBJNM' )
                      ( name = 'NODE_NAME'  rollname = 'RSSHNODENAME_MAXLEN' )
                      ( name = 'VALUE_SID'  rollname = 'RSSID' ) ).
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
    LOOP AT generated_numbers( ) INTO DATA(number).
      highest = nmax( val1 = highest val2 = number ).
    ENDLOOP.
    SELECT node_table FROM zzxxmla1_hietab INTO TABLE @DATA(registered).
    LOOP AT registered INTO DATA(table).
      highest = nmax( val1 = highest val2 = number_of( name = table-node_table prefix = c_node_prefix ) ).
    ENDLOOP.
    result = highest + 1.
  ENDMETHOD.

  METHOD generated_numbers.
    DATA(node_pattern) = |{ c_node_prefix }%|.
    DATA(closure_pattern) = |{ c_closure_prefix }%|.
    DATA(path_pattern) = |{ c_path_prefix }%|.
    DATA(view_pattern) = |{ c_rest_view_prefix }%|.
    DATA(ddl_pattern) = |{ c_rest_ddl_prefix }%|.
    SELECT DISTINCT tabname FROM dd02l
      WHERE tabname LIKE @node_pattern OR tabname LIKE @closure_pattern OR tabname LIKE @path_pattern
         OR tabname LIKE @view_pattern
      INTO TABLE @DATA(tables).
    SELECT DISTINCT ddlname FROM ddddlsrc WHERE ddlname LIKE @ddl_pattern INTO TABLE @DATA(sources).
    DATA(names) = VALUE string_table( FOR t IN tables ( CONV string( t-tabname ) ) ).
    DATA(prefixes) = VALUE string_table( ( c_node_prefix ) ( c_closure_prefix ) ( c_path_prefix )
                                         ( c_rest_view_prefix ) ).
    LOOP AT names INTO DATA(name).
      LOOP AT prefixes INTO DATA(prefix).
        DATA(number) = number_of( name = name prefix = prefix ).
        IF number > 0 AND NOT line_exists( result[ table_line = number ] ).
          APPEND number TO result.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT sources INTO DATA(source).
      number = number_of( name = source-ddlname prefix = c_rest_ddl_prefix ).
      IF number > 0 AND NOT line_exists( result[ table_line = number ] ).
        APPEND number TO result.
      ENDIF.
    ENDLOOP.
    SORT result ASCENDING.
  ENDMETHOD.

  METHOD number_of.
    DATA(text) = condense( CONV string( name ) ).
    IF strlen( text ) <> strlen( prefix ) + 7 OR substring( val = text len = strlen( prefix ) ) <> prefix.
      RETURN.
    ENDIF.
    DATA(digits) = substring( val = text off = strlen( prefix ) ).
    IF digits CO '0123456789'.
      result = CONV i( digits ).
    ENDIF.
  ENDMETHOD.

  METHOD tables_of_number.
    result = VALUE #( node      = table_name( prefix = c_node_prefix number = number )
                      closure   = table_name( prefix = c_closure_prefix number = number )
                      path      = table_name( prefix = c_path_prefix number = number )
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
