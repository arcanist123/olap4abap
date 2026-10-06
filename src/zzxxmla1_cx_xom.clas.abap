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
"! An error while a schema is read into its definition (ZZXXMLA1_CL_SCHEMA_DEF): eigenbase-xom's
"! XOMException. The constructor of every element puts "In", the element's name and ": " in front of the message of an
"! error inside it (SchemaDef), so the message reads like the reference's, e.g. "In Schema: In Cube: Attribute 'name' is
"! unset and has no default value.".
CLASS zzxxmla1_cx_xom DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! the message of the exception (Throwable.getMessage)
    DATA error_message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING error_message TYPE string
                previous      LIKE previous OPTIONAL.
    METHODS if_message~get_text REDEFINITION.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cx_xom IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->error_message = error_message.
  ENDMETHOD.

  METHOD if_message~get_text.
    result = error_message.
  ENDMETHOD.

ENDCLASS.