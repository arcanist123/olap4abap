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
"! The answers to Discover requests, kept in table ZZXXMLA1_DSCACHE (gzipped) for c_valid_hours, so that a client's
"! metadata calls (Excel asks for the catalogs, cubes, dimensions, hierarchies, levels and properties whenever it
"! connects or refreshes a PivotTable) do not read and parse the schemas again. An answer is keyed by the text of
"! everything of the request it depends on (ZZXXMLA1_CL_XMLA_HANDLER=>discover_key), hashed; the text itself is kept
"! and compared, so two requests never share an answer. Only answers without fault are kept.
"! The cache is cleared whenever a file of the server (ZZXXMLA1_CL_FILES: datasources.xml, the schemas) is written or
"! deleted, and when the time master data are filled; an answer made while a file changed is not kept. Master data and
"! facts changed in BW (members, cardinalities) are seen after c_valid_hours at most.
CLASS zzxxmla1_cl_discover_cache DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CONSTANTS c_valid_hours TYPE i VALUE 12.

    "! The kept answer of the request, if it is younger than c_valid_hours; initial otherwise.
    "! @parameter key | the request's text (ZZXXMLA1_CL_XMLA_HANDLER=>discover_key)
    CLASS-METHODS read
      IMPORTING !key          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! Keeps the answer of the request, unless a file of the server changed since the answer was started; deletes the
    "! answers older than c_valid_hours. The caller commits.
    "! @parameter key | the request's text (ZZXXMLA1_CL_XMLA_HANDLER=>discover_key)
    "! @parameter started | when the request was started to be answered (UTC)
    CLASS-METHODS write
      IMPORTING !key          TYPE string
                request_type  TYPE csequence
                response      TYPE string
                started       TYPE timestampl.
    "! Deletes every kept answer; the caller commits.
    CLASS-METHODS clear.
  PROTECTED SECTION.
  PRIVATE SECTION.
    "! The table key of the request's text: its SHA-1, 40 hex digits; initial if it cannot be computed.
    CLASS-METHODS hash
      IMPORTING !key          TYPE string
      RETURNING VALUE(result) TYPE zzxxmla1_dscache-cache_key.
    "! The oldest creation time of an answer that is still valid.
    CLASS-METHODS valid_since
      RETURNING VALUE(result) TYPE timestampl.
    CLASS-METHODS compress
      IMPORTING !text         TYPE string
      RETURNING VALUE(result) TYPE xstring.
    CLASS-METHODS decompress
      IMPORTING !data         TYPE xstring
      RETURNING VALUE(result) TYPE string.
ENDCLASS.



CLASS zzxxmla1_cl_discover_cache IMPLEMENTATION.

  METHOD read.
    DATA(cache_key) = hash( key ).
    IF cache_key IS INITIAL.
      RETURN.
    ENDIF.
    SELECT SINGLE request, created_at, response FROM zzxxmla1_dscache
      WHERE cache_key = @cache_key
      INTO @DATA(row).
    IF sy-subrc <> 0 OR row-request <> key OR row-created_at < valid_since( ).
      RETURN.
    ENDIF.
    result = decompress( row-response ).
  ENDMETHOD.

  METHOD write.
    DATA(cache_key) = hash( key ).
    IF cache_key IS INITIAL OR response IS INITIAL.
      RETURN.
    ENDIF.
    " a schema accepted while the answer was made: the answer may be of the old one
    SELECT SINGLE @abap_true FROM zzxxmla1_file
      WHERE changed_at >= @started
      INTO @DATA(changed).
    IF changed = abap_true.
      RETURN.
    ENDIF.
    DATA(row) = VALUE zzxxmla1_dscache( cache_key    = cache_key
                                        request_type = request_type
                                        created_at   = started
                                        request      = key
                                        response     = compress( response ) ).
    IF row-response IS INITIAL.
      RETURN.
    ENDIF.
    DATA(since) = valid_since( ).
    DELETE FROM zzxxmla1_dscache WHERE created_at < @since.
    MODIFY zzxxmla1_dscache FROM @row.
  ENDMETHOD.

  METHOD clear.
    DELETE FROM zzxxmla1_dscache.
  ENDMETHOD.

  METHOD hash.
    TRY.
        cl_abap_message_digest=>calculate_hash_for_char( EXPORTING if_algorithm  = 'SHA1'
                                                                   if_data       = key
                                                         IMPORTING ef_hashstring = DATA(hex) ).
        result = hex.
      CATCH cx_abap_message_digest.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD valid_since.
    " whole seconds cut, not rounded: CONV timestamp rounds 59.6 to 60, which subtractsecs refuses
    DATA now TYPE timestamp.
    GET TIME STAMP FIELD now.
    result = cl_abap_tstmp=>subtractsecs( tstmp = now secs = c_valid_hours * 3600 ) ##TYPE.
  ENDMETHOD.

  METHOD compress.
    TRY.
        cl_abap_gzip=>compress_text( EXPORTING text_in    = text
                                               conversion = 'UTF-8'
                                     IMPORTING gzip_out   = result ).
      CATCH cx_parameter_invalid_range cx_sy_buffer_overflow cx_sy_conversion_codepage cx_sy_compression_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

  METHOD decompress.
    TRY.
        cl_abap_gzip=>decompress_text( EXPORTING gzip_in    = data
                                                 conversion = 'UTF-8'
                                       IMPORTING text_out   = result ).
      CATCH cx_parameter_invalid_range cx_sy_buffer_overflow cx_sy_conversion_codepage cx_sy_compression_error.
        CLEAR result.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
