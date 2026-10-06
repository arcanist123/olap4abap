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
"! The roll-up of the values of tuples in an evaluation context (AggregateCalc.aggregate): the callback the calculations
"! of the engine (the placeholder of a compound slicer, a visual total member) use, so that they do not depend on the
"! engine class. Implemented by the engine. The types are copies of the engine's, to keep the objects independent.
INTERFACE zzxxmla1_if_mdx_roll_up
  PUBLIC.

  TYPES:
    BEGIN OF ty_member,
      hierarchy     TYPE string,
      hier_id       TYPE i,
      measure_index TYPE i,
      ordinal       TYPE i,
      key           TYPE string,
      key_level     TYPE i,
      path          TYPE string,
      unique_name   TYPE string,
      caption       TYPE string,
      level         TYPE i,
      level_name    TYPE string,
      level_number  TYPE i,
      parent_unique TYPE string,
      children      TYPE i,
      display_info  TYPE i,
      calculated    TYPE abap_bool,
      solve_order   TYPE i,
      is_null       TYPE abap_bool,
      calc_name     TYPE string,
    END OF ty_member,
    ty_t_member TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY,
    ty_tuple    TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY,
    ty_t_tuple  TYPE STANDARD TABLE OF ty_tuple WITH EMPTY KEY.

  "! The values of the tuples (the expression, else the cell of the context) rolled up with the aggregator of the
  "! measure of the context (sum; count rolls up as sum; min, max), non-empty off.
  METHODS roll_up
    IMPORTING evaluator     TYPE REF TO zzxxmla1_if_mdx_evaluator
              tuples        TYPE ty_t_tuple
              value         TYPE REF TO zzxxmla1_cl_mdx_node OPTIONAL
    RETURNING VALUE(result) TYPE zzxxmla1_if_mdx_evaluator=>ty_value
    RAISING   zzxxmla1_cx_xmla.

ENDINTERFACE.
