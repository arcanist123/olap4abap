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
"! evaluator uses for the formulas of calculated members and for format strings. Implemented by the engine.
INTERFACE zzxxmla1_if_mdx_calc
  PUBLIC.

  "! The value of a scalar expression in the context of the evaluator.
  METHODS evaluate
    IMPORTING evaluator     TYPE REF TO zzxxmla1_cl_mdx_evaluator
              node          TYPE REF TO zzxxmla1_cl_mdx_node
    RETURNING VALUE(result) TYPE zzxxmla1_cl_mdx_evaluator=>ty_value
    RAISING   zzxxmla1_cx_xmla.

ENDINTERFACE.