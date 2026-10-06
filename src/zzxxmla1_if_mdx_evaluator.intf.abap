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
"! The evaluation of a resolved expression in an evaluation context: Calc (Calc.evaluate), which the
"! An evaluation context (Evaluator): the current member of each hierarchy, savepoint/restore and the value of the
"! current cell, implemented by ZZXXMLA1_CL_MDX_EVALUATOR (RolapEvaluator). Calculations (ZZXXMLA1_IF_MDX_CALC) see the
"! evaluator through it. The types are copies of the schema reader's and the evaluator's, to keep the objects
"! independent.
INTERFACE zzxxmla1_if_mdx_evaluator
  PUBLIC.

  TYPES:
    BEGIN OF ty_member,
      hierarchy     TYPE string,   " unique name of the hierarchy
      hier_id       TYPE i,        " id of the hierarchy: 0 for Measures, else the position in the model
      measure_index TYPE i,        " position in the measures (Measures hierarchy only)
      ordinal       TYPE i,        " position in the hierarchy in hierarchy order, the All member first (0)
      key           TYPE string,   " value of the level column; empty for the All member
      key_level     TYPE i,        " the level in the model (1 the first below the All level), 0: the All member
      path          TYPE string,   " the keys of the model levels down to key_level (ZZXXMLA1_CL_MODEL)
      unique_name   TYPE string,
      caption       TYPE string,
      level         TYPE i,        " id of the level
      level_name    TYPE string,   " unique name of the level
      level_number  TYPE i,
      parent_unique TYPE string,
      children      TYPE i,
      display_info  TYPE i,
      calculated    TYPE abap_bool, " a calculated member of the query (RolapCalculatedMember)
      solve_order   TYPE i,         " calculated members: SOLVE_ORDER, else 0
      is_null       TYPE abap_bool, " the null member of the hierarchy (RolapHierarchy.getNullMember)
      "! a member made while the query runs (VisualTotalMember) has the unique name of the member it stands for: the
      "! key of its calculation (get_calculation); empty for any other member
      calc_name     TYPE string,
    END OF ty_member,
    ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.
  TYPES:
    "! A value (an Object in the reference): empty is null; else a double (number, or special INF, -INF or NAN), an integer
    "! (number), a string (text), a boolean, an evaluation error (text: the message) or the OrderKey of a member
    "! (member; text its key).
    BEGIN OF ty_value,
      empty   TYPE abap_bool,
      kind    TYPE string,
      number  TYPE f,
      special TYPE string,
      text    TYPE string,
      boolean TYPE abap_bool,
      member  TYPE ty_member,
    END OF ty_value.

  "! A child evaluator with a copy of this one's context.
  METHODS push
    RETURNING VALUE(result) TYPE REF TO zzxxmla1_if_mdx_evaluator.
  METHODS get_parent
    RETURNING VALUE(result) TYPE REF TO zzxxmla1_if_mdx_evaluator.
  METHODS get_schema_reader
    RETURNING VALUE(result) TYPE REF TO zzxxmla1_if_mdx_schema_reader.
  "! A savepoint: restore( savepoint ) undoes the changes made after it.
  METHODS savepoint
    RETURNING VALUE(result) TYPE i.
  METHODS restore
    IMPORTING savepoint TYPE i.
  "! Makes the member the current member of its hierarchy.
  "! @parameter result | the previous current member of the hierarchy
  METHODS set_context
    IMPORTING member        TYPE ty_member
    RETURNING VALUE(result) TYPE ty_member.
  "! Makes the members (a tuple) current, in turn.
  METHODS set_context_members
    IMPORTING members TYPE ty_t_member.
  "! The current member of a hierarchy.
  METHODS get_context
    IMPORTING hierarchy     TYPE i
    RETURNING VALUE(result) TYPE ty_member.
  "! The current members, one per hierarchy in the order of the cube (Measures first).
  METHODS get_members
    RETURNING VALUE(result) TYPE ty_t_member.
  "! Sets the members of the slicer as the context and keeps them as the slicer members.
  METHODS set_slicer_context
    IMPORTING members TYPE ty_t_member.
  METHODS get_slicer_members
    RETURNING VALUE(result) TYPE ty_t_member.
  "! setCellReader as RolapResult.executeBody calls it before the cells are computed: the cell reader does not
  "! change here (the facts), but the command is recorded, so the command stack has the reference's shape (the context
  "! stack of an infinite loop).
  METHODS set_cell_reader.
  METHODS is_non_empty
    RETURNING VALUE(result) TYPE abap_bool.
  METHODS set_non_empty
    IMPORTING non_empty TYPE abap_bool.
  METHODS is_eval_axes
    RETURNING VALUE(result) TYPE abap_bool.
  METHODS set_eval_axes
    IMPORTING eval_axes TYPE abap_bool.
  "! The value of the cell of the current context: the formula of the calculation that expands first, with the
  "! calculation's hierarchy at its default member (setContextIn), or else the value read from the facts.
  METHODS evaluate_current
    RETURNING VALUE(result) TYPE ty_value
    RAISING   zzxxmla1_cx_xmla.
  "! Whether the cell of the current context is empty: its value is empty, or no fact row is in it (Fact Count 0).
  METHODS current_is_empty
    RETURNING VALUE(result) TYPE abap_bool
    RAISING   zzxxmla1_cx_xmla.
  "! The format string of the cell (getFormatString): the format of the non-All member with the highest solve order
  "! that has one (a stored measure's format string, a calculated member's format expression evaluated in the
  "! context), else Standard.
  METHODS get_format_string
    RETURNING VALUE(result) TYPE string
    RAISING   zzxxmla1_cx_xmla.

ENDINTERFACE.
