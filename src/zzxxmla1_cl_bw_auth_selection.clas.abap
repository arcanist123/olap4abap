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
"! The selection of a query in BW's names, as the check of BW's analysis authorizations takes it (docs/next-steps.md,
"! Next: BW's MDX on InfoProviders, step 3; the selection the authorisations' step 5a checks): the query's members
"! (ZZXXMLA1_CL_MDX_ENGINE=>members) as ZZXXMLA1_CL_BW_AUTH's members, a factor per slicer, axis and subselect axis
"! (a tuple of the query is one tuple of each), and the members the query names by an identifier, also those its
"! tuples do not show (the node of a Children). A member is a value of a characteristic's flat hierarchy (its key, the
"! All member the aggregate) or a node or leaf of a BW hierarchy (its name and InfoObject); members of no
"! characteristic (Measures, another hierarchy of a characteristic's table) are left out, a characteristic not in a
"! tuple is aggregated. A tuple with the All member of a BW hierarchy is left out: BW's hierarchies have none.
CLASS zzxxmla1_cl_bw_auth_selection DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_selection,
        "! per factor its tuples, and its name (Slicer, Axis0, ..., Subselect1 Axis0)
        factors TYPE zzxxmla1_cl_bw_auth_sql=>ty_factors,
        names   TYPE string_table,
        "! the members the query names
        named   TYPE zzxxmla1_cl_bw_auth=>ty_tuple,
        "! a factor has no tuple: the query shows nothing
        empty   TYPE abap_bool,
      END OF ty_selection.

    CLASS-METHODS of_members
      IMPORTING !members      TYPE zzxxmla1_cl_mdx_engine=>ty_members
      RETURNING VALUE(result) TYPE ty_selection.
    "! A member as text: a value its characteristic and key, a node its hierarchy, version, name and InfoObject, the
    "! aggregate its characteristic and :.
    CLASS-METHODS member_text
      IMPORTING !member       TYPE zzxxmla1_cl_bw_auth=>ty_member
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_names TYPE HASHED TABLE OF string WITH UNIQUE KEY table_line.

    "! The tuples as a factor; a tuple with the All member of a BW hierarchy is left out.
    CLASS-METHODS factor
      IMPORTING tuples        TYPE zzxxmla1_cl_mdx_engine=>ty_t_tuple
                reader        TYPE REF TO zzxxmla1_cl_mdx_schema_reader
                named         TYPE ty_names
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_selection.
    "! The member in the check's terms; initial (no iobjnm) for a member of no characteristic; all: the All member of
    "! a BW hierarchy.
    CLASS-METHODS auth_member
      IMPORTING !member TYPE zzxxmla1_cl_mdx_engine=>ty_member
                reader  TYPE REF TO zzxxmla1_cl_mdx_schema_reader
                named   TYPE ty_names
      EXPORTING result  TYPE zzxxmla1_cl_bw_auth=>ty_member
                !all    TYPE abap_bool.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_selection IMPLEMENTATION.

  METHOD of_members.
    DATA(reader) = members-schema_reader.
    DATA(named) = VALUE ty_names( FOR n IN members-named ( n-unique_name ) ).
    IF members-has_slicer = abap_true.
      APPEND factor( tuples = members-slicer reader = reader named = named ) TO result-factors.
      APPEND `Slicer` TO result-names.
    ENDIF.
    LOOP AT members-axes INTO DATA(axis).
      APPEND |Axis{ sy-tabix - 1 }| TO result-names.
      APPEND factor( tuples = axis reader = reader named = named ) TO result-factors.
    ENDLOOP.
    LOOP AT members-subcubes INTO DATA(subcube).
      APPEND |Subselect Axis{ sy-tabix - 1 }| TO result-names.
      APPEND factor( tuples = subcube reader = reader named = named ) TO result-factors.
    ENDLOOP.
    LOOP AT result-factors INTO DATA(factor).
      IF factor IS INITIAL.
        result-empty = abap_true.
      ENDIF.
    ENDLOOP.
    LOOP AT members-named INTO DATA(member).
      auth_member( EXPORTING member = member reader = reader named = named IMPORTING result = DATA(auth) ).
      IF auth-iobjnm IS NOT INITIAL AND NOT line_exists( result-named[ table_line = auth ] ).
        APPEND auth TO result-named.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD factor.
    LOOP AT tuples INTO DATA(tuple).
      DATA(auth_tuple) = VALUE zzxxmla1_cl_bw_auth=>ty_tuple( ).
      DATA(left_out) = abap_false.
      LOOP AT tuple INTO DATA(member).
        auth_member( EXPORTING member = member reader = reader named = named
                     IMPORTING result = DATA(auth) all = DATA(all) ).
        IF all = abap_true.
          left_out = abap_true.
          EXIT.
        ENDIF.
        IF auth-iobjnm IS NOT INITIAL.
          APPEND auth TO auth_tuple.
        ENDIF.
      ENDLOOP.
      IF left_out = abap_false.
        APPEND auth_tuple TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD auth_member.
    CLEAR: result, all.
    DATA(bw) = reader->bw_member( member ).
    IF bw-characteristic IS INITIAL.
      RETURN.
    ENDIF.
    IF bw-hierarchy IS NOT INITIAL AND bw-all = abap_true.
      all = abap_true.
      RETURN.
    ENDIF.
    result = VALUE #( iobjnm = to_upper( bw-characteristic )
                      named  = xsdbool( line_exists( named[ table_line = member-unique_name ] ) ) ).
    IF bw-hierarchy IS NOT INITIAL.
      result-kind = zzxxmla1_cl_bw_auth=>c_kind-node.
      result-value = bw-name.
      result-hienm = bw-hierarchy.
      result-version = bw-version.
      result-node_iobjnm = bw-iobj.
    ELSEIF bw-all = abap_true.
      result-kind = zzxxmla1_cl_bw_auth=>c_kind-aggregate.
    ELSE.
      result-kind = zzxxmla1_cl_bw_auth=>c_kind-value.
      result-value = bw-name.
    ENDIF.
  ENDMETHOD.

  METHOD member_text.
    result = SWITCH #( member-kind
                       WHEN zzxxmla1_cl_bw_auth=>c_kind-aggregate THEN |{ member-iobjnm } :|
                       WHEN zzxxmla1_cl_bw_auth=>c_kind-node
                       THEN condense( |{ member-iobjnm } { member-hienm } { member-version } | &&
                                      |{ member-value } ({ member-node_iobjnm })| )
                       ELSE |{ member-iobjnm } '{ member-value }'| ).
  ENDMETHOD.

ENDCLASS.
