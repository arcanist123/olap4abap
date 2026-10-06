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
"! The calculation of a visual total member (VisualTotalMember: Aggregate of the members it totals): the cell of the
"! context rolled up over its members (AggregateCalc.aggregate with a ValueCalc). Created by ZZXXMLA1_CL_MDX_ENGINE,
"! whose global friend it is.
CLASS zzxxmla1_cl_mdx_vtotal_calc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_mdx_calc.
    METHODS constructor
      IMPORTING engine   TYPE REF TO zzxxmla1_cl_mdx_engine
                member   TYPE zzxxmla1_cl_mdx_engine=>ty_member
                children TYPE zzxxmla1_cl_mdx_engine=>ty_t_member.
    "! The member the visual total stands for (VisualTotalMember.getMember).
    DATA member TYPE zzxxmla1_cl_mdx_engine=>ty_member READ-ONLY.
    "! The stored members it totals (getChildMemberList).
    DATA children TYPE zzxxmla1_cl_mdx_engine=>ty_t_member READ-ONLY.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA engine TYPE REF TO zzxxmla1_cl_mdx_engine.
ENDCLASS.



CLASS zzxxmla1_cl_mdx_vtotal_calc IMPLEMENTATION.

  METHOD constructor.
    me->engine = engine.
    me->member = member.
    me->children = children.
  ENDMETHOD.

  METHOD zzxxmla1_if_mdx_calc~evaluate.
    result = engine->roll_up( evaluator = evaluator
                              tuples = VALUE #( FOR child IN children ( VALUE #( ( child ) ) ) ) ).
  ENDMETHOD.

ENDCLASS.