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
"! A request the schema API (ZZXXMLA1_CL_SCHEMA_API) refuses: the HTTP status and the message of the JSON error.
CLASS zzxxmla1_cx_api_refused DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the HTTP status of the answer
    DATA status  TYPE i READ-ONLY.
    "! the message of the JSON error
    DATA message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING status  TYPE i
                message TYPE string.
    METHODS if_message~get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cx_api_refused IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( ).
    me->status = status.
    me->message = message.
  ENDMETHOD.

  METHOD if_message~get_text.
    result = message.
  ENDMETHOD.

ENDCLASS.