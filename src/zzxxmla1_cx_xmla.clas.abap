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
CLASS zzxxmla1_cx_xmla DEFINITION
  PUBLIC
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

  PUBLIC SECTION.
    " A SOAP fault exactly as the reference sends it (xmla.XmlaException): a fault code made of the kind (Client,
    " Server, MustUnderstand) and a code, a fixed text per code, and the description of the error. The fault
    " string is the fixed text, a blank and the description; the detail repeats the description behind "The olap4abap
    " XML: ". Faults travel with HTTP status 200, as the reference answers them.
    DATA fault_code   TYPE string READ-ONLY.
    DATA fault_string TYPE string READ-ONLY.
    DATA description  TYPE string READ-ONLY.
    DATA error_code   TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING
        fault_code   TYPE string
        fault_string TYPE string
        description  TYPE string
        error_code   TYPE string DEFAULT `3238658121`
        previous     LIKE previous OPTIONAL.

    "! Fault of a code: kind is Client, Server or MustUnderstand, code e.g. 00HSBA01, text the fixed text of
    "! the code (the XmlaConstants *_FAULT_FS).
    CLASS-METHODS of_code
      IMPORTING kind          TYPE string
                code          TYPE string
                text          TYPE string
                description   TYPE string
                error_code    TYPE string DEFAULT `3238658121`
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cx_xmla.
    "! Raises the fault of a code (of_code). NetWeaver 7.50 has no RAISE EXCEPTION with an expression.
    CLASS-METHODS raise_code
      IMPORTING kind        TYPE string
                code        TYPE string
                text        TYPE string
                description TYPE string
                error_code  TYPE string DEFAULT `3238658121`
      RAISING   zzxxmla1_cx_xmla.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.

CLASS zzxxmla1_cx_xmla IMPLEMENTATION.
  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    super->constructor( previous = previous ).
    me->fault_code   = fault_code.
    me->fault_string = fault_string.
    me->description  = description.
    me->error_code   = error_code.
  ENDMETHOD.

  METHOD raise_code.
    DATA(fault) = of_code( kind = kind code = code text = text description = description error_code = error_code ).
    RAISE EXCEPTION fault.
  ENDMETHOD.

  METHOD of_code.
    result = NEW #( fault_code   = |SOAP-ENV:{ kind }.{ code }|
                    fault_string = |{ text } { description }|
                    description  = description
                    error_code   = error_code ).
  ENDMETHOD.
ENDCLASS.