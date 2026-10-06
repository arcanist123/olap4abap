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
"! The schema reader as the evaluation context sees it (SchemaReader), implemented by ZZXXMLA1_CL_MDX_SCHEMA_READER
"! (RolapSchemaReader). The types are copies of the schema reader's, to keep the objects independent.
INTERFACE zzxxmla1_if_mdx_schema_reader
  PUBLIC.

  CONSTANTS c_measures TYPE i VALUE 0.
  TYPES ty_t_id TYPE STANDARD TABLE OF i WITH EMPTY KEY.
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
    "! A calculated member of the query with its formula (Formula): the resolved expression, the format expression
    "! (FORMAT_EXP_PARSED, if any) and whether the expression calls Aggregate (containsAggregateFunction). The
    "! placeholder of a compound slicer (RolapResult.CompoundSlicerRolapMember) has a calculation of its own
    "! (getCompiledExpression, kept by the root evaluator) instead of an expression, and is not calculated in the query
    "! (cube scope).
    BEGIN OF ty_calculated_member,
      member             TYPE ty_member,
      expression         TYPE REF TO zzxxmla1_cl_mdx_node,
      format_expression  TYPE REF TO zzxxmla1_cl_mdx_node,
      contains_aggregate TYPE abap_bool,
      cube_scope         TYPE abap_bool,
    END OF ty_calculated_member,
    ty_t_calculated_member TYPE STANDARD TABLE OF ty_calculated_member WITH EMPTY KEY.
  TYPES:
    BEGIN OF ty_hierarchy,
      id              TYPE i,
      dimension       TYPE i,
      name            TYPE string,   " Measures, or dimension.hierarchy as version 3 schemas name them
      unique_name     TYPE string,
      has_all         TYPE abap_bool,
      all_member_name TYPE string,
      levels          TYPE ty_t_id,
      model           TYPE zzxxmla1_cl_model=>ty_hierarchy,
    END OF ty_hierarchy,
    ty_t_hierarchy TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.

  METHODS get_hierarchies RETURNING VALUE(result) TYPE ty_t_hierarchy.
  "! The default member (RolapHierarchy.init): the hierarchy's defaultMember, else the first root member (the All
  "! member, without one the first member of the first level), for Measures the first measure.
  METHODS get_default_member
    IMPORTING hierarchy     TYPE i
    RETURNING VALUE(result) TYPE ty_member.
  "! The member of a measure (1 is the first).
  METHODS measure_member
    IMPORTING index         TYPE i
    RETURNING VALUE(result) TYPE ty_member.
  "! The measures of the cube, as ZZXXMLA1_CL_MODEL gives them (1 is the first).
  METHODS get_measures
    RETURNING VALUE(result) TYPE zzxxmla1_cl_model=>ty_t_measure.
  "! The calculation of a calculated member: a visual total by its calc_name, else by its unique name.
  METHODS get_calculation
    IMPORTING member        TYPE ty_member
    RETURNING VALUE(result) TYPE ty_calculated_member.

ENDINTERFACE.
