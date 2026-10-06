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
"! A request the API refuses: the HTTP status and the message of the JSON error.
CLASS lcx_refused DEFINITION INHERITING FROM cx_static_check FINAL.
  PUBLIC SECTION.
    DATA status TYPE i READ-ONLY.
    DATA message TYPE string READ-ONLY.
    METHODS constructor
      IMPORTING status  TYPE i
                message TYPE string.
    METHODS if_message~get_text REDEFINITION.
ENDCLASS.
