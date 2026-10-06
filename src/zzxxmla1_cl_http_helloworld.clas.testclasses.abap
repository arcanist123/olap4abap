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
*"* use this source file for your ABAP unit test classes
CLASS ltc_helloworld DEFINITION DEFERRED.
CLASS zzxxmla1_cl_http_helloworld DEFINITION LOCAL FRIENDS ltc_helloworld.

CLASS ltc_helloworld DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zzxxmla1_cl_http_helloworld.

    METHODS setup.
    METHODS body_is_hello_world FOR TESTING.
ENDCLASS.


CLASS ltc_helloworld IMPLEMENTATION.

  METHOD setup.
    cut = NEW #( ).
  ENDMETHOD.

  METHOD body_is_hello_world.
    cl_abap_unit_assert=>assert_equals(
      act = cut->get_body( )
      exp = `Hello World` ).
  ENDMETHOD.

ENDCLASS.