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
* Sets up olap4abap after the package is imported (ZZXXMLA1_CL_SETUP): the tables and the data sources file (and
* deletes the schema builder's old copies below /schema/: it is served from the code); with the checkbox also the
* clinic demo (ZZXXMLA1_CL_BW_CLINIC_GEN), which deletes and creates InfoArea ZCLINIC's InfoCube ZCLVISIT and aDSO
* ZCLVISITA with their InfoObjects, with at most p_maxvis visits if that is not 0; with the other checkbox the wide
* demo (ZZXXMLA1_CL_BW_WIDE_GEN), which deletes and creates InfoArea ZXMLWIDE's InfoCube ZXMLWIDE and aDSO ZXMLWIDEA
* with the characteristics ZXMLAD00 to ZXMLAD99, with p_wrecs records (0: 1,000,000). Many records take longer than a
* dialog step may: then run it in the background (F9). A demo always deletes all its objects, and creates its InfoCube
* only with p_cube and its aDSO only with p_adso. With p_auth the analysis authorization scenarios and their test
* users (ZZXXMLA1_CL_BW_AUTH_GEN), with the clinic demo or alone, the users with the password p_apwd (none: nobody can
* log on as them); it is not kept anywhere.
REPORT zzxxmla1_setup.

SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_clinic AS CHECKBOX.
SELECTION-SCREEN COMMENT 4(70) t_clinic FOR FIELD p_clinic.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(35) t_maxvis FOR FIELD p_maxvis.
PARAMETERS p_maxvis TYPE i.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_auth AS CHECKBOX.
SELECTION-SCREEN COMMENT 4(70) t_auth FOR FIELD p_auth.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(35) t_apwd FOR FIELD p_apwd.
PARAMETERS p_apwd TYPE c LENGTH 40 LOWER CASE.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_wide AS CHECKBOX.
SELECTION-SCREEN COMMENT 4(70) t_wide FOR FIELD p_wide.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
SELECTION-SCREEN COMMENT 1(35) t_wrecs FOR FIELD p_wrecs.
PARAMETERS p_wrecs TYPE i.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_cube AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN COMMENT 4(70) t_cube FOR FIELD p_cube.
SELECTION-SCREEN END OF LINE.
SELECTION-SCREEN BEGIN OF LINE.
PARAMETERS p_adso AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN COMMENT 4(70) t_adso FOR FIELD p_adso.
SELECTION-SCREEN END OF LINE.

INITIALIZATION.
  t_clinic = 'Also generate the clinic demo (BW objects, data, schemas, catalogs)'.
  t_maxvis = 'Clinic demo: max. visits (0: all)'.
  t_auth = 'Also the analysis authorization scenarios and their test users'.
  t_apwd = 'Test users: password (none: no logon)'.
  t_wide = 'Also generate the wide demo (100 characteristics, BW objects, data)'.
  t_wrecs = 'Wide demo: records (0: 1,000,000)'.
  t_cube = 'Demos: create the InfoCube (all objects are deleted either way)'.
  t_adso = 'Demos: create the aDSO (all objects are deleted either way)'.

AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-name = 'P_APWD'.
      screen-invisible = 1.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

START-OF-SELECTION.
  LOOP AT NEW zzxxmla1_cl_setup( )->run( clinic            = p_clinic
                                         clinic_max_visits = p_maxvis
                                         wide              = p_wide
                                         wide_records      = p_wrecs
                                         cube              = p_cube
                                         adso              = p_adso
                                         authorizations    = p_auth
                                         password          = p_apwd ) INTO DATA(line).
    WRITE / line.
  ENDLOOP.
