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
"! An error while a cell is evaluated: EvaluationException (FunUtil.newEvalException). The engine
"! catches it per cell, as RolapResult.executeStripe does, and the cell's value is the exception as text
"! (olap4abap.EvaluationException: and the message). Raised elsewhere (an axis, the slicer) it is the
"! fault Server.00HSBD02 "XMLA MDX execute failed" with the message.
CLASS zzxxmla1_cx_mdx_evaluation DEFINITION
  PUBLIC
  INHERITING FROM zzxxmla1_cx_xmla
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! the message of the exception
    DATA error_message TYPE string READ-ONLY.

    METHODS constructor
      IMPORTING error_message TYPE string.
    "! FunUtil.newEvalException( null, message ).
    CLASS-METHODS create
      IMPORTING error_message TYPE string
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cx_mdx_evaluation.
    "! Raises FunUtil.newEvalException( null, message ) (create). NetWeaver 7.50 has no RAISE EXCEPTION with an
    "! expression.
    CLASS-METHODS raise_error
      IMPORTING error_message TYPE string
      RAISING   zzxxmla1_cx_mdx_evaluation.
    "! Throwable.toString: the class name of the exception and its message.
    METHODS to_text
      RETURNING VALUE(result) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zzxxmla1_cx_mdx_evaluation IMPLEMENTATION.

  METHOD constructor ##ADT_SUPPRESS_GENERATION.
    " outside a cell (e.g. on an axis) the execution fails, as the reference server answers it
    super->constructor( fault_code   = `SOAP-ENV:Server.00HSBD02`
                        fault_string = |XMLA MDX execute failed { error_message }|
                        description  = error_message ).
    me->error_message = error_message.
  ENDMETHOD.

  METHOD raise_error.
    DATA(error) = create( error_message ).
    RAISE EXCEPTION error.
  ENDMETHOD.

  METHOD create.
    result = NEW #( error_message ).
  ENDMETHOD.

  METHOD to_text.
    result = |olap4abap.EvaluationException: { error_message }|.
  ENDMETHOD.

ENDCLASS.