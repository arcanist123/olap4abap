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
"! A failed SQL statement (ZZXXMLA1_CL_SQL): not expected in a correct schema, so unchecked, as SQL errors
"! are runtime exceptions. The XMLA handler answers it with a SOAP fault that carries the statement and the
"! database's message.
CLASS zzxxmla1_cx_sql DEFINITION
  PUBLIC
  INHERITING FROM cx_no_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the statement that failed
    DATA statement     TYPE string READ-ONLY.
    "! the database's message
    DATA error_message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING statement     TYPE string
                error_message TYPE string
                previous      LIKE previous OPTIONAL.
    METHODS if_message~get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cx_sql IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->statement = statement.
    me->error_message = error_message.
  ENDMETHOD.

  METHOD if_message~get_text.
    result = |{ error_message } (SQL: { statement })|.
  ENDMETHOD.

ENDCLASS.
