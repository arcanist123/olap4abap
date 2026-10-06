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
* Sets up olap4abap after the package is imported (ZZXXMLA1_CL_SETUP): the tables, the schema builder's files and the
* data sources file; with the checkbox also the clinic demo (ZZXXMLA1_CL_BW_CLINIC_GEN), which deletes and creates
* InfoArea ZCLINIC's InfoCube ZCLVISIT and aDSO ZCLVISITA with their InfoObjects.
REPORT zzxxmla1_setup.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_clinic AS CHECKBOX.
SELECTION-SCREEN COMMENT 4(70) t_clinic FOR FIELD p_clinic.
SELECTION-SCREEN END OF LINE.

INITIALIZATION.
  t_clinic = 'Also generate the clinic demo (BW objects, data, schemas, catalogs)'.

START-OF-SELECTION.
  LOOP AT NEW zzxxmla1_cl_setup( )->run( clinic = p_clinic ) INTO DATA(line).
    WRITE / line.
  ENDLOOP.