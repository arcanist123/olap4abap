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
"! The calculation of the placeholder of a compound slicer (the CacheCalc around RolapResult's GenericCalc
"! "EvalForSlicer"): the cell of the context rolled up over the tuples of the slicer (AggregateCalc.aggregate with a
"! ValueCalc). Created by ZZXXMLA1_CL_MDX_ENGINE.
CLASS zzxxmla1_cl_mdx_slicer_calc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_mdx_calc.
    METHODS constructor
      IMPORTING engine TYPE REF TO zzxxmla1_if_mdx_roll_up
                tuples TYPE zzxxmla1_if_mdx_roll_up=>ty_t_tuple.
    "! The tuples of the slicer (CompoundSlicerRolapMember.tupleList), for isOnSameHierarchyChain.
    DATA tuples TYPE zzxxmla1_if_mdx_roll_up=>ty_t_tuple READ-ONLY.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA engine TYPE REF TO zzxxmla1_if_mdx_roll_up.
ENDCLASS.



CLASS zzxxmla1_cl_mdx_slicer_calc IMPLEMENTATION.

  METHOD constructor.
    me->engine = engine.
    me->tuples = tuples.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_calc~evaluate.
    result = engine->roll_up( evaluator = evaluator tuples = tuples ).
  ENDMETHOD.

ENDCLASS.
