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
"! The wide demo (docs/wide-demo.md): a provider with many characteristics, for trying the schema builder and the
"! engine on a wide model. It creates InfoArea ZXMLWIDE with
"! - the characteristics ZXMLAD00 to ZXMLAD99 (NUMC 4, with master data and no attributes), 1,000 members each,
"! - the key figure ZXMLAKF,
"! - the InfoCube ZXMLWIDE (ten BW dimensions of ten characteristics) and the cube-type aDSO ZXMLWIDEA, each loaded
"!   with the same records, 1,000 unless another number is given,
"! and no views, schema or catalog: the schema builder makes those.
"! The records come from a seeded pseudo-random generator (every run gives the same ones): every characteristic takes
"! one of its 1,000 members, the key figure a whole number from 1 to 1,000. They are built and loaded in packages, so
"! the memory needed does not grow with their number.
"! Every run deletes the aDSO, the cube, the views of the characteristics and the InfoObjects listed here and creates
"! them again: never point it at objects that hold data you want to keep. A run with many records takes longer than a
"! dialog work process may: run program ZZXXMLA1_SETUP in the background.
CLASS zzxxmla1_cl_bw_wide_gen DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS c_infoarea TYPE rsinfoarea VALUE 'ZXMLWIDE'.
    CONSTANTS c_cube     TYPE rsinfocube VALUE 'ZXMLWIDE'.
    CONSTANTS c_adso     TYPE rsoadsonm VALUE 'ZXMLWIDEA'.
    CONSTANTS c_records  TYPE i VALUE 1000.

    "! Generates everything; the log of the run.
    "! @parameter records | the records in each provider; 0: c_records
    METHODS run
      IMPORTING records       TYPE i DEFAULT 0
      RETURNING VALUE(result) TYPE string_table.

  PROTECTED SECTION.
  PRIVATE SECTION.
    CONSTANTS c_seed            TYPE int8 VALUE 20261006.
    CONSTANTS c_characteristics TYPE i VALUE 100.
    CONSTANTS c_members         TYPE i VALUE 1000.
    CONSTANTS c_per_dimension   TYPE i VALUE 10.
    CONSTANTS c_max_amount      TYPE i VALUE 1000.
    CONSTANTS c_package         TYPE i VALUE 100000.
    CONSTANTS c_key_figure      TYPE rsiobjnm VALUE 'ZXMLAKF'.

    TYPES ty_t_iobjnm TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.

    DATA log TYPE string_table.
    DATA seed TYPE int8.
    "! the sum of the key figure over the records of the last load
    DATA amount_total TYPE int8.

    METHODS write IMPORTING text TYPE csequence.
    "! ZXMLAD00 to ZXMLAD99.
    METHODS characteristics RETURNING VALUE(result) TYPE ty_t_iobjnm.
    METHODS all_iobjnm RETURNING VALUE(result) TYPE ty_t_iobjnm.

    "! The next pseudo-random number from 1 to n (Park and Miller's minimal standard generator).
    METHODS random IMPORTING n TYPE i RETURNING VALUE(result) TYPE i.
    "! Appends count records: the next pseudo-random member of each characteristic and the key figure.
    "! @parameter fields | the components of the characteristics, in their order
    "! @parameter amount | the component of the key figure
    METHODS fill_package
      IMPORTING fields TYPE string_table
                amount TYPE string
                count  TYPE i
      CHANGING  table  TYPE STANDARD TABLE.

    METHODS delete_all.
    METHODS delete_cube.
    METHODS delete_adso.
    METHODS delete_views.
    METHODS delete_infoobjects.
    METHODS ensure_infoarea.
    METHODS create_characteristic IMPORTING iobjnm TYPE rsiobjnm.
    METHODS create_key_figure.
    METHODS activate_infoobjects.
    METHODS create_cube.
    METHODS activate_cube.
    "! The keys 1 to c_members into the characteristic's attribute table (P table), which gives them their SIDs.
    METHODS load_master_data IMPORTING iobjnm TYPE rsiobjnm.
    METHODS load_cube IMPORTING records TYPE i.
    METHODS create_adso.
    "! The name BW generated for a table or view of the aDSO (CL_RSO_ADSO=>GET_TABLNM).
    METHODS adso_table IMPORTING type TYPE rsdsotabtype RETURNING VALUE(result) TYPE tabname.
    METHODS load_adso IMPORTING records TYPE i.
    "! Counts the rows of a fact table or view and sums the key figure.
    METHODS verify IMPORTING source TYPE csequence records TYPE i.

    "! The field of an InfoObject in BW's generated tables (RSD_FIELDNM_GET_FROM_IOBJNM), checked against the structure.
    METHODS iobj_field
      IMPORTING struct        TYPE REF TO cl_abap_structdescr
                iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE string.
    METHODS write_return IMPORTING return TYPE bapiret2_t.
    METHODS write_exception IMPORTING error TYPE REF TO cx_root.
    METHODS write_messages IMPORTING messages TYPE rs_t_msg.
ENDCLASS.



CLASS zzxxmla1_cl_bw_wide_gen IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    LOOP AT run( ) INTO DATA(line).
      out->write( line ).
    ENDLOOP.
  ENDMETHOD.

  METHOD run.
    CLEAR log.
    DATA(count) = COND i( WHEN records > 0 THEN records ELSE c_records ).
    write( |{ c_characteristics } characteristics of { c_members } members, { count } records| ).

    delete_all( ).
    ensure_infoarea( ).
    LOOP AT characteristics( ) INTO DATA(iobjnm).
      create_characteristic( iobjnm ).
    ENDLOOP.
    create_key_figure( ).
    activate_infoobjects( ).
    create_cube( ).
    activate_cube( ).
    LOOP AT characteristics( ) INTO iobjnm.
      load_master_data( iobjnm ).
    ENDLOOP.
    load_cube( count ).
    verify( source = |/BIC/F{ c_cube }| records = count ).
    create_adso( ).
    load_adso( count ).
    verify( source = adso_table( cl_rsdso_constants=>n_c_viewtype_reporting ) records = count ).
    result = log.
  ENDMETHOD.

  METHOD write.
    APPEND text TO log.
    " in the background also into the job log, which keeps what was done if the job is cancelled
    IF sy-batch = abap_true.
      MESSAGE text TYPE 'S'.
    ENDIF.
  ENDMETHOD.

  METHOD characteristics.
    DATA number TYPE n LENGTH 2.
    DO c_characteristics TIMES.
      number = sy-index - 1.
      APPEND |ZXMLAD{ number }| TO result.
    ENDDO.
  ENDMETHOD.

  METHOD all_iobjnm.
    result = characteristics( ).
    APPEND c_key_figure TO result.
  ENDMETHOD.

  METHOD random.
    seed = ( seed * 48271 ) MOD 2147483647.
    result = seed MOD n + 1.
  ENDMETHOD.

  METHOD fill_package.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DO count TIMES.
      APPEND INITIAL LINE TO table ASSIGNING <row>.
      LOOP AT fields INTO DATA(field).
        ASSIGN COMPONENT field OF STRUCTURE <row> TO <value>.
        <value> = random( c_members ).
      ENDLOOP.
      DATA(value) = random( c_max_amount ).
      ASSIGN COMPONENT amount OF STRUCTURE <row> TO <value>.
      <value> = value.
      amount_total = amount_total + value.
    ENDDO.
  ENDMETHOD.

  METHOD delete_all.
    " the providers and the views use the characteristics, so they go first
    delete_adso( ).
    delete_cube( ).
    delete_views( ).
    delete_infoobjects( ).
  ENDMETHOD.

  METHOD delete_cube.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA subrc TYPE sysubrc.
    DATA messages TYPE rs_t_msg.
    SELECT SINGLE infocube FROM rsdcube WHERE infocube = @c_cube INTO @DATA(found).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    SELECT SINGLE infocube FROM rsdcube WHERE infocube = @c_cube AND objvers = @rs_c_objvers-active
      INTO @DATA(active) ##NEEDED.
    IF sy-subrc <> 0.
      " a cube that was saved but never activated (a cancelled run): IWP_ICUBE_DELETE asks whether to delete its
      " data, which a background job cancels
      CALL FUNCTION 'RSDG_CUBE_DELETE'
        EXPORTING
          i_infocube       = c_cube
          i_write_protocol = rs_c_false
          i_progress       = rs_c_false
          i_with_impact    = rs_c_false
          i_with_cto       = rs_c_false
        IMPORTING
          e_t_msg          = messages
          e_subrc          = subrc.
      write( |delete inactive InfoCube { found }: | &&
             |{ COND string( WHEN subrc = 0 THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
      IF subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        write_messages( messages ).
      ENDIF.
      RETURN.
    ENDIF.
    CALL FUNCTION 'IWP_ICUBE_DELETE'
      EXPORTING
        i_infocube = c_cube
      IMPORTING
        e_subrc    = subrc
      TABLES
        et_return  = return.
    write( |delete InfoCube { found }: { COND string( WHEN subrc = 0 THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
    IF subrc <> 0.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD delete_adso.
    IF cl_rso_adso_api=>exist( c_adso ) <> rs_c_true.
      RETURN.
    ENDIF.
    TRY.
        cl_rso_adso_api=>delete( i_adsonm         = c_adso
                                 i_with_cto       = rs_c_false
                                 i_force_deletion = rs_c_true ).
        COMMIT WORK AND WAIT.
        write( |delete aDSO { c_adso }: done| ).
      CATCH cx_rs_all_msg INTO DATA(error).
        ROLLBACK WORK.
        write( |delete aDSO { c_adso }: FAILED| ).
        write_exception( error ).
    ENDTRY.
  ENDMETHOD.

  METHOD delete_views.
    " the schema builder generates views of the characteristics when it accepts a schema
    DATA(generator) = NEW zzxxmla1_cl_bw_view_gen( ).
    LOOP AT characteristics( ) INTO DATA(iobjnm).
      TRY.
          IF generator->delete( iobjnm ) = abap_true.
            write( |delete view of { iobjnm }: done| ).
          ENDIF.
        CATCH cx_dd_ddl_exception INTO DATA(error).
          write( |delete view of { iobjnm }: FAILED, { error->get_text( ) }| ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

  METHOD delete_infoobjects.
    DATA iobjnms TYPE rsd_t_c30.
    DATA messages TYPE rs_t_msg.
    DATA subrc TYPE sy-subrc.
    LOOP AT all_iobjnm( ) INTO DATA(iobjnm).
      SELECT SINGLE iobjnm FROM rsdiobj WHERE iobjnm = @iobjnm INTO @DATA(found) ##NEEDED.
      IF sy-subrc = 0.
        APPEND iobjnm TO iobjnms.
      ENDIF.
    ENDLOOP.
    IF iobjnms IS INITIAL.
      RETURN.
    ENDIF.
    CALL FUNCTION 'RSDG_IOBJ_MULTI_DELETE'
      EXPORTING
        i_t_iobjnm        = iobjnms
        i_check_dependent = rs_c_false
        i_manual          = rs_c_false
      IMPORTING
        e_t_msg           = messages
        e_subrc           = subrc.
    write( |delete InfoObjects: { lines( iobjnms ) } requested, subrc { subrc }| ).
    IF subrc <> 0.
      write_messages( messages ).
    ENDIF.
  ENDMETHOD.

  METHOD ensure_infoarea.
    SELECT SINGLE infoarea FROM rsdarea WHERE infoarea = @c_infoarea AND objvers = 'A' INTO @DATA(found) ##NEEDED.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.
    NEW cl_new_awb_area( )->if_rsawbn_folder_tree~create_node(
      EXPORTING  i_parentname      = ''
                 i_nodename        = CONV #( c_infoarea )
                 i_txtsh           = 'Wide demo'
                 i_txtlg           = 'Wide demo data (100 characteristics)'
                 i_insertbehaviour = '0'
      EXCEPTIONS cancelled         = 1
                 OTHERS            = 2 ).
    IF sy-subrc = 0.
      COMMIT WORK AND WAIT.
      write( |InfoArea { c_infoarea } created| ).
    ELSE.
      write( |InfoArea { c_infoarea } FAILED, subrc { sy-subrc }, { sy-msgid } { sy-msgno } { sy-msgv1 }| ).
    ENDIF.
  ENDMETHOD.

  METHOD create_characteristic.
    DATA return TYPE bapiret2_t.
    DATA return_line TYPE bapiret2.
    DATA iobj TYPE bapi6108-infoobject.
    DATA attributes TYPE STANDARD TABLE OF bapi6108at WITH DEFAULT KEY.
    DATA(text) = CONV rstxtlg( |Dimension { iobjnm+6(2) }| ).
    " with master data, so it has an attribute table with its members, but without attributes
    DATA(details) = VALUE bapi6108(
      infoobject = iobjnm
      version    = rs_c_objvers-modified
      type       = rsd_c_objtp-charact
      textshort  = text
      textlong   = text
      infoarea   = c_infoarea
      chabasnm   = iobjnm
      datatp     = 'NUMC'
      intlen     = 4
      leng       = 4
      outputlen  = 4
      attribfl   = rs_c_true ).
    CALL FUNCTION 'BAPI_IOBJ_CREATE'
      EXPORTING
        details     = details
      IMPORTING
        infoobject  = iobj
        return      = return_line
      TABLES
        attributes  = attributes
        returntable = return.
    IF iobj IS INITIAL.
      write( |create { iobjnm }: FAILED| ).
      APPEND return_line TO return.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD create_key_figure.
    DATA return TYPE bapiret2_t.
    DATA return_line TYPE bapiret2.
    DATA iobj TYPE bapi6108-infoobject.
    DATA(details) = VALUE bapi6108(
      infoobject = c_key_figure
      version    = rs_c_objvers-modified
      type       = rsd_c_objtp-keyfigure
      textshort  = 'Amount'
      textlong   = 'Amount'
      infoarea   = c_infoarea
      kyftp      = 'NUM'
      datatp     = 'DEC'
      intlen     = 17
      leng       = 17
      decimals   = 2
      aggrgen    = 'SUM'
      aggrexc    = 'SUM' ).
    CALL FUNCTION 'BAPI_IOBJ_CREATE'
      EXPORTING
        details     = details
      IMPORTING
        infoobject  = iobj
        return      = return_line
      TABLES
        returntable = return.
    IF iobj IS INITIAL.
      write( |create { c_key_figure }: FAILED| ).
      APPEND return_line TO return.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD activate_infoobjects.
    DATA infoobjects TYPE STANDARD TABLE OF bapi6108io WITH DEFAULT KEY.
    DATA errors TYPE STANDARD TABLE OF bapi6108io WITH DEFAULT KEY.
    DATA return TYPE bapiret2_t.
    LOOP AT all_iobjnm( ) INTO DATA(iobjnm).
      APPEND iobjnm TO infoobjects.
    ENDLOOP.
    CALL FUNCTION 'BAPI_IOBJ_ACTIVATE_MULTIPLE'
      TABLES
        infoobjects       = infoobjects
        return            = return
        infoobjects_error = errors.
    write( |activate InfoObjects: { lines( infoobjects ) } requested, { lines( errors ) } in error| ).
    IF errors IS NOT INITIAL.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD create_cube.
    " an InfoCube has at most 13 dimensions of its own: ten of ten characteristics each
    CONSTANTS suffixes TYPE c LENGTH 10 VALUE '123456789A'.
    DATA dimension_table TYPE STANDARD TABLE OF bapi6112di WITH DEFAULT KEY.
    DATA infoobjects TYPE STANDARD TABLE OF bapi6112io WITH DEFAULT KEY.
    DATA dimension_infoobjects TYPE STANDARD TABLE OF bapi6112dio WITH DEFAULT KEY.
    DATA valid TYPE STANDARD TABLE OF rsdicvaliobj WITH DEFAULT KEY.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA cube TYPE bapi6112-infocube.
    DATA position TYPE rsposit.
    DATA dimension TYPE rsdimension.
    DATA(package_dimension) = CONV rsdimension( |{ c_cube }P| ).
    APPEND VALUE #( infocube  = c_cube
                    objvers   = rs_c_objvers-modified
                    dimension = package_dimension
                    textlong  = 'Data Package'
                    iobjtp    = 'DPA' ) TO dimension_table.
    LOOP AT VALUE ty_t_iobjnm( ( '0CHNGID' ) ( '0RECORDTP' ) ( '0REQUID' ) ) INTO DATA(iobjnm).
      position = position + 1.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = rs_c_objvers-modified
                      dimension  = package_dimension
                      posit      = sy-tabix
                      infoobject = iobjnm ) TO dimension_infoobjects.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = rs_c_objvers-modified
                      posit      = position
                      infoobject = iobjnm
                      iobjtp     = 'DPA' ) TO infoobjects.
    ENDLOOP.
    LOOP AT characteristics( ) INTO iobjnm.
      DATA(index) = sy-tabix - 1.
      DATA(in_dimension) = index MOD c_per_dimension + 1.
      dimension = |{ c_cube }{ substring( val = suffixes off = index DIV c_per_dimension len = 1 ) }|.
      IF in_dimension = 1.
        APPEND VALUE #( infocube  = c_cube
                        objvers   = rs_c_objvers-modified
                        dimension = dimension
                        textlong  = |Dimensions { iobjnm+6(2) }-{ iobjnm+6(1) }9|
                        iobjtp    = 'CHA' ) TO dimension_table.
      ENDIF.
      position = position + 1.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = rs_c_objvers-modified
                      dimension  = dimension
                      posit      = in_dimension
                      infoobject = iobjnm ) TO dimension_infoobjects.
      APPEND VALUE #( infocube   = c_cube
                      objvers    = rs_c_objvers-modified
                      posit      = position
                      infoobject = iobjnm
                      iobjtp     = 'CHA' ) TO infoobjects.
    ENDLOOP.
    position = position + 1.
    APPEND VALUE #( infocube   = c_cube
                    objvers    = rs_c_objvers-modified
                    posit      = position
                    infoobject = c_key_figure
                    iobjtp     = rsd_c_objtp-keyfigure ) TO infoobjects.
    DATA(details) = VALUE bapi6112( infocube = c_cube
                                    objvers  = rs_c_objvers-modified
                                    textlong = 'Wide demo (100 characteristics)'
                                    infoarea = c_infoarea
                                    cubetype = rsd_c_cubetype-basic_ic ).
    CALL FUNCTION 'BAPI_CUBE_CREATE'
      EXPORTING
        details              = details
      IMPORTING
        infocube             = cube
      TABLES
        dimensions           = dimension_table
        infoobjects          = infoobjects
        dimensioninfoobjects = dimension_infoobjects
        return               = return
        rsdicvaliobj         = valid.
    write( |create InfoCube { c_cube }: { COND string( WHEN cube IS NOT INITIAL THEN `saved` ELSE `FAILED` ) }| ).
    IF cube IS INITIAL.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD activate_cube.
    DATA return TYPE STANDARD TABLE OF bapiret2 WITH DEFAULT KEY.
    DATA active TYPE bapi6112-activfl.
    CALL FUNCTION 'BAPI_CUBE_ACTIVATE'
      EXPORTING
        infocube              = c_cube
      IMPORTING
        activation_successful = active
      TABLES
        return                = return.
    write( |activate InfoCube { c_cube }: { COND string( WHEN active = abap_true THEN `active` ELSE `FAILED` ) }| ).
    IF active <> abap_true.
      write_return( return ).
    ENDIF.
  ENDMETHOD.

  METHOD load_master_data.
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    FIELD-SYMBOLS <row> TYPE any.
    FIELD-SYMBOLS <value> TYPE any.
    DATA data TYPE REF TO data.
    DATA attributes TYPE rsd_t_iobjnm.
    DATA messages TYPE rsarr_t_idocstate.
    DATA subrc TYPE sy-subrc.
    cl_abap_typedescr=>describe_by_name( EXPORTING  p_name         = |/BIC/P{ iobjnm }|
                                         RECEIVING  p_descr_ref    = DATA(descr)
                                         EXCEPTIONS type_not_found = 1
                                                    OTHERS         = 2 ).
    IF sy-subrc <> 0.
      write( |load { iobjnm }: FAILED, no table /BIC/P{ iobjnm }| ).
      RETURN.
    ENDIF.
    DATA(table_type) = cl_abap_tabledescr=>create( CAST cl_abap_structdescr( descr ) ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    DO c_members TIMES.
      APPEND INITIAL LINE TO <table> ASSIGNING <row>.
      ASSIGN COMPONENT |/BIC/{ iobjnm }| OF STRUCTURE <row> TO <value>.
      <value> = sy-index.
      ASSIGN COMPONENT 'OBJVERS' OF STRUCTURE <row> TO <value>.
      <value> = rs_c_objvers-active.
    ENDDO.
    CALL FUNCTION 'RSDMD_WRITE_ATTRIBUTES_TEXTS'
      EXPORTING
        i_iobjnm               = iobjnm
        i_tabclass             = rsdmd_c_tabclass-md
        i_t_attr               = attributes
      IMPORTING
        e_t_idocstate          = messages
        e_subrc                = subrc
      TABLES
        i_t_table              = <table>
      EXCEPTIONS
        attribute_name_error   = 1
        iobj_not_found         = 2
        generate_program_error = 3
        OTHERS                 = 4.
    IF sy-subrc = 0 AND subrc = 0.
      COMMIT WORK AND WAIT.
    ELSE.
      ROLLBACK WORK.
      write( |load { iobjnm }: FAILED, subrc { sy-subrc } { subrc }| ).
    ENDIF.
  ENDMETHOD.

  METHOD load_cube.
    " RSDRI_CUBE_WRITE_PACKAGE takes rows of the cube's T-view (/BIC/V<cube>2): InfoObject names without /BIC/
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    DATA data TYPE REF TO data.
    DATA request TYPE rsrequnr.
    DATA written TYPE i.
    DATA messages TYPE rsdri_ts_msg.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( |/BIC/V{ c_cube }2| ) ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    DATA(fields) = VALUE string_table( FOR c IN characteristics( ) ( CONV #( c ) ) ).
    seed = c_seed.
    amount_total = 0.
    DATA(left) = records.
    DATA(package) = 0.
    WHILE left > 0.
      package = package + 1.
      DATA(count) = nmin( val1 = left val2 = c_package ).
      CLEAR <table>.
      fill_package( EXPORTING fields = fields amount = CONV #( c_key_figure ) count = count
                    CHANGING  table  = <table> ).
      CALL FUNCTION 'RSDRI_CUBE_WRITE_PACKAGE'
        EXPORTING
          i_infocube         = c_cube
          i_curr_conversion  = rs_c_false
        IMPORTING
          e_requid           = request
          e_records          = written
          e_ts_msg           = messages
        CHANGING
          c_t_data           = <table>
        EXCEPTIONS
          infocube_not_found = 1
          illegal_input      = 2
          rollback_error     = 3
          duplicate_records  = 4
          request_locked     = 5
          not_transactional  = 6
          inherited_error    = 7
          OTHERS             = 8.
      DATA(subrc) = sy-subrc.
      IF subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
      ENDIF.
      write( |load { c_cube } package { package }: { count } records sent, { written } written, | &&
             |{ COND string( WHEN subrc = 0 THEN |request { request }| ELSE |FAILED, subrc { subrc }| ) }| ).
      IF subrc <> 0.
        RETURN.
      ENDIF.
      left = left - count.
    ENDWHILE.
  ENDMETHOD.

  METHOD create_adso.
    DATA objects TYPE cl_rso_adso_api=>tn_t_object.
    DATA messages TYPE rs_t_msg.
    DATA error TYPE REF TO cx_root.
    objects = VALUE #( FOR c IN characteristics( ) ( iobjnm = c sid_determination_mode = 'S' ) ).
    APPEND VALUE #( iobjnm = c_key_figure aggregation = 'SUM' ) TO objects.
    TRY.
        DATA(flags) = cl_rso_adso_api=>get_adso_flags_from_model_tmpl( cl_rso_adso_api=>tn_c_model_tmpl-cube_like ).
        cl_rso_adso_api=>create( EXPORTING i_adsonm      = c_adso
                                           i_text        = 'Wide demo (100 characteristics, aDSO)'
                                           i_infoarea    = c_infoarea
                                           i_s_adsoflags = flags
                                           i_t_object    = objects
                                           i_t_dimension = VALUE #( )
                                           i_with_cto    = rs_c_false
                                 IMPORTING e_t_msg       = messages ).
        COMMIT WORK AND WAIT.
        write( |create aDSO { c_adso }: active| ).
      CATCH cx_rs_all_msg cx_rs_failed INTO error.
        ROLLBACK WORK.
        write( |create aDSO { c_adso }: FAILED| ).
        write_exception( error ).
        RETURN.
    ENDTRY.
    write_messages( VALUE #( FOR m IN messages WHERE ( msgty = 'E' OR msgty = 'A' ) ( m ) ) ).
  ENDMETHOD.

  METHOD adso_table.
    TRY.
        DATA(tables) = cl_rso_adso=>get_tablnm( c_adso ).
        result = VALUE #( tables[ dsotabtype = type ]-name OPTIONAL ).
      CATCH cx_rs_not_found.
        CLEAR result.
    ENDTRY.
    IF result IS INITIAL.
      write( |aDSO { c_adso }: no { type } table| ).
    ENDIF.
  ENDMETHOD.

  METHOD load_adso.
    " the same records as the cube's: the generator starts again from the seed
    FIELD-SYMBOLS <table> TYPE STANDARD TABLE.
    DATA data TYPE REF TO data.
    DATA inserted TYPE int4.
    DATA messages TYPE rs_t_msg.
    DATA activation_requests TYPE rsdso_t_tsn.
    DATA request TYPE rspm_request_tsn.
    DATA(inbound) = adso_table( cl_rsdso_dsotable=>c_tabtype_aq ).
    IF inbound IS INITIAL.
      RETURN.
    ENDIF.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( inbound ) ).
    DATA(table_type) = cl_abap_tabledescr=>create( line ).
    CREATE DATA data TYPE HANDLE table_type.
    ASSIGN data->* TO <table>.
    DATA(fields) = VALUE string_table( FOR c IN characteristics( ) ( iobj_field( struct = line iobjnm = c ) ) ).
    DATA(amount) = iobj_field( struct = line iobjnm = c_key_figure ).
    seed = c_seed.
    amount_total = 0.
    DATA(left) = records.
    DATA(package) = 0.
    WHILE left > 0.
      package = package + 1.
      DATA(count) = nmin( val1 = left val2 = c_package ).
      CLEAR <table>.
      fill_package( EXPORTING fields = fields amount = amount count = count
                    CHANGING  table  = <table> ).
      CALL FUNCTION 'RSDSO_WRITE_API'
        EXPORTING
          i_adsonm            = c_adso
          i_activate_data     = rs_c_true
          it_data             = <table>
        IMPORTING
          e_lines_inserted    = inserted
          et_msg              = messages
          e_upd_req_tsn       = request
          et_act_req_tsn      = activation_requests
        EXCEPTIONS
          write_failed        = 1
          activation_failed   = 2
          datastore_not_found = 3
          OTHERS              = 4.
      DATA(subrc) = sy-subrc.
      IF subrc = 0.
        COMMIT WORK AND WAIT.
      ELSE.
        ROLLBACK WORK.
      ENDIF.
      write( |load aDSO { c_adso } package { package }: { count } records sent, { inserted } written, | &&
             |{ lines( activation_requests ) } activated, | &&
             |{ COND string( WHEN subrc = 0 THEN `done` ELSE |FAILED, subrc { subrc }| ) }| ).
      IF subrc <> 0.
        write_messages( messages ).
        RETURN.
      ENDIF.
      left = left - count.
    ENDWHILE.
  ENDMETHOD.

  METHOD verify.
    DATA rows TYPE i.
    DATA total TYPE p LENGTH 16 DECIMALS 2.
    IF source IS INITIAL.
      RETURN.
    ENDIF.
    DATA(line) = CAST cl_abap_structdescr( cl_abap_typedescr=>describe_by_name( source ) ).
    DATA(list) = |COUNT(*), SUM( { iobj_field( struct = line iobjnm = c_key_figure ) } )|.
    SELECT SINGLE (list) FROM (source) INTO (@rows, @total).
    write( |{ source }: { rows } rows, amount { total } (generated: { records } records, amount { amount_total })| ).
  ENDMETHOD.

  METHOD iobj_field.
    DATA field TYPE rsd_fieldnm.
    CALL FUNCTION 'RSD_FIELDNM_GET_FROM_IOBJNM'
      EXPORTING
        i_name     = iobjnm
      IMPORTING
        e_ddname   = field
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    DATA(subrc) = sy-subrc.
    result = field.
    DATA(components) = struct->get_components( ).
    IF subrc <> 0 OR NOT line_exists( components[ name = result ] ).
      write( |{ iobjnm }: no field { result } in { struct->get_relative_name( ) }| ).
    ENDIF.
  ENDMETHOD.

  METHOD write_exception.
    DATA(current) = error.
    WHILE current IS BOUND.
      write( |  { current->get_text( ) }| ).
      IF current IS INSTANCE OF cx_rs_all_msg.
        DATA(with_messages) = CAST cx_rs_all_msg( current ).
        write_messages( with_messages->t_msg ).
        IF with_messages->r_log IS BOUND.
          write_messages( with_messages->r_log->get_messages( ) ).
        ENDIF.
      ENDIF.
      current = current->previous.
    ENDWHILE.
  ENDMETHOD.

  METHOD write_return.
    LOOP AT return INTO DATA(line) WHERE message IS NOT INITIAL.
      write( |  [{ line-type }] { line-message }| ).
    ENDLOOP.
  ENDMETHOD.

  METHOD write_messages.
    LOOP AT messages INTO DATA(message).
      MESSAGE ID message-msgid TYPE 'S' NUMBER message-msgno
        WITH message-msgv1 message-msgv2 message-msgv3 message-msgv4 INTO DATA(text).
      write( |  [{ message-msgty }] { text }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
