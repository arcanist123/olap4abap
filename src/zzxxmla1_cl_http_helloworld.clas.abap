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
CLASS zzxxmla1_cl_http_helloworld DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_http_extension.
  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS get_body RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_http_helloworld IMPLEMENTATION.

  METHOD if_http_extension~handle_request.
    server->response->set_status( code = 200 reason = 'OK' ).
    server->response->set_content_type( 'text/plain; charset=utf-8' ).
    server->response->set_cdata( get_body( ) ).
  ENDMETHOD.

  METHOD get_body.
    result = |Hello World|.
  ENDMETHOD.

ENDCLASS.
