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
"! A BW hierarchy that cannot be copied (ZZXXMLA1_CL_BW_HIERARCHY_COPY): one olap4abap refuses (a duplicate value with
"! another subtree, a value both an inner node and a leaf, more than one current row of RSRHIEDIR_OLAP, a time- or
"! version-dependent one), one whose tables were never created, or a copy that differs from BW. Unchecked: the query
"! that resolves the hierarchy fails, and the XMLA handler answers it with a SOAP fault carrying the message.
CLASS zzxxmla1_cx_bw_hierarchy DEFINITION
  PUBLIC
  INHERITING FROM cx_no_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    DATA error_message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING error_message TYPE string
                previous      LIKE previous OPTIONAL.
    METHODS if_message~get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cx_bw_hierarchy IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->error_message = error_message.
  ENDMETHOD.

  METHOD if_message~get_text.
    result = error_message.
  ENDMETHOD.

ENDCLASS.
