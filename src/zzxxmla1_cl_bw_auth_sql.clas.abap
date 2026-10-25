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
"! The check of a query's selection against a user's analysis authorizations in HANA (docs/next-steps.md, Now:
"! analysis authorisations, Decisions of 2026-10-24): the answers of ZZXXMLA1_CL_BW_AUTH's check, with no hierarchy
"! expanded in ABAP.
"! The profile is the user's region per node (ZZXXMLA1_CL_BW_AUTH=>profile, read without expansion): per applying
"! authorization and authorization-relevant characteristic its flags (all, aggregate) and flat ranges, and its
"! hierarchy lines by name, each with two copies of its hierarchy (ZZXXMLA1_CL_BW_HIERARCHY_COPY): the slice valid at
"! the key date (the nodes the line shows) and the slice valid at the line's date (the values it authorizes). The
"! copies are made when the profile is read, the tables of a characteristic too (create_tables), never by a check.
"! A line is expanded on the path table of its copy: its node's occurrences are the path rows whose level member has
"! the line's node name and InfoObject, the occurrence's own row (TLEVEL = DEPTH) names what the line shows; type 0 the
"! node itself, 1 its subtree, 2 its subtree down to the line's level, 3 (and 4) every occurrence (the roots' rows,
"! TLEVEL 1). A leaf of the copy is named by the characteristic and its key, so a line on a leaf matches by name too,
"! and the values a line authorizes are its leaves' keys.
"! The request is the query's members (a value by its key, a node by its hierarchy, name and InfoObject, the
"! aggregate) and its tuples as factors: a tuple of the query is one tuple of each factor (an axis, the slicer), so a
"! crossjoin is not multiplied out in ABAP. One statement answers the check: the first member, the named ones first,
"! that no authorization admits, with its reason, else a combination of the factors' tuples outside every sub-cube
"! (a characteristic no tuple of the combination has is aggregated: a bit mask per tuple of its characteristics and
"! per authorization of the aggregated ones it allows). Values are matched by key: EQ and BT as BW compares them, CP as
"! LIKE (* %, + _, the others escaped) and, on a key of digits (NUMC), with the pattern's leading digits as a number
"! of the key's length; the not-assigned value is the key ''. The provider, a variable and an unrestricted user
"! (0BI_ALL) are answered before, without a statement.
CLASS zzxxmla1_cl_bw_auth_sql DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    "! the factors of a query's selection: per factor its tuples; a tuple of the query is one of each
    TYPES ty_factors TYPE STANDARD TABLE OF zzxxmla1_cl_bw_auth=>ty_selection WITH EMPTY KEY.
    "! a copy of a hierarchy slice as the statement reads it; hiesid 0: the slice has none (no slice at the date)
    TYPES: BEGIN OF ty_copy,
             hiesid TYPE i,
             sver   TYPE string,
             path   TYPE tabname,
           END OF ty_copy.
    "! a hierarchy line with the copy of the slice at the key date and the one at its own date
    TYPES: BEGIN OF ty_line,
             line       TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line,
             key_copy   TYPE ty_copy,
             value_copy TYPE ty_copy,
           END OF ty_line.
    TYPES ty_lines TYPE STANDARD TABLE OF ty_line WITH EMPTY KEY.
    TYPES ty_copies TYPE STANDARD TABLE OF ty_copy WITH EMPTY KEY.
    "! the profile: the characteristics, the flat parts and the hierarchy lines with their copies
    TYPES: BEGIN OF ty_profile,
             characteristics TYPE zzxxmla1_cl_bw_auth=>ty_characteristics,
             flats           TYPE zzxxmla1_cl_bw_auth=>ty_flats,
             lines           TYPE ty_lines,
           END OF ty_profile.
    TYPES: BEGIN OF ty_statement,
             sql    TYPE string,
             params TYPE zzxxmla1_cl_sql=>ty_t_param,
           END OF ty_statement.

    "! The check of the user on the provider at the key date: the region read without expansion, its copies made.
    CLASS-METHODS read
      IMPORTING !user         TYPE xubname
                provider      TYPE csequence
                key_date      TYPE d DEFAULT zzxxmla1_cl_bw_auth=>c_key_date
                today         TYPE d DEFAULT sy-datum
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth_sql
      RAISING   zzxxmla1_cx_bw_provider.
    "! The check of a region and a given profile, for the unit tests.
    CLASS-METHODS create
      IMPORTING region        TYPE REF TO zzxxmla1_cl_bw_auth
                profile       TYPE ty_profile
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_cl_bw_auth_sql.

    "! Whether the query's selection, its tuples as one factor, is in the region (ZZXXMLA1_CL_BW_AUTH's check).
    METHODS check
      IMPORTING selection     TYPE zzxxmla1_cl_bw_auth=>ty_selection
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! Whether the query's selection, a tuple of each factor, is in the region; no tuple if a factor has none.
    METHODS check_product
      IMPORTING factors       TYPE ty_factors
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! The check of members without their tuples (ZZXXMLA1_CL_BW_AUTH's check_members).
    METHODS check_members
      IMPORTING members       TYPE zzxxmla1_cl_bw_auth=>ty_tuple
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! The authorizations that apply to the provider.
    METHODS applying
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_auths.

  PROTECTED SECTION.
  PRIVATE SECTION.
    "! a member of the request: the query's member and the key it is matched by (a value's '' for #)
    TYPES: BEGIN OF ty_request_member,
             member TYPE zzxxmla1_cl_bw_auth=>ty_member,
             key    TYPE string,
           END OF ty_request_member.
    TYPES ty_request_members TYPE STANDARD TABLE OF ty_request_member WITH EMPTY KEY.
    "! a member of a tuple of a factor (member 0: the tuple has none) and the tuple's characteristics as bits
    TYPES: BEGIN OF ty_request_tuple,
             factor TYPE i,
             tuple  TYPE i,
             member TYPE i,
             mask   TYPE i,
           END OF ty_request_tuple.
    TYPES ty_request_tuples TYPE STANDARD TABLE OF ty_request_tuple WITH EMPTY KEY.
    "! the request: the distinct members of the authorization-relevant characteristics in the order the query's tuples
    "! show them first, the tuples of each factor, the number of factors (0: no tuple, members only)
    TYPES: BEGIN OF ty_request,
             members TYPE ty_request_members,
             tuples  TYPE ty_request_tuples,
             factors TYPE i,
           END OF ty_request.
    "! a column of a derived table of bound values: its name and SQL type
    TYPES: BEGIN OF ty_column,
             name TYPE string,
             type TYPE string,
           END OF ty_column.
    TYPES ty_columns TYPE STANDARD TABLE OF ty_column WITH EMPTY KEY.
    TYPES ty_rows TYPE STANDARD TABLE OF zzxxmla1_cl_sql=>ty_t_param WITH EMPTY KEY.
    "! BW's CP pattern as LIKE parts: the pattern, and of a pattern that starts with digits these digits and the
    "! pattern of the rest (for a NUMC key)
    TYPES: BEGIN OF ty_like,
             pattern TYPE string,
             number  TYPE string,
             rest    TYPE string,
           END OF ty_like.

    "! The characteristics a mask has room for (a bit each in an INTEGER).
    CONSTANTS c_max_characteristics TYPE i VALUE 30.
    CONSTANTS c_key_copy TYPE c LENGTH 1 VALUE 'K'.
    CONSTANTS c_value_copy TYPE c LENGTH 1 VALUE 'V'.

    DATA region TYPE REF TO zzxxmla1_cl_bw_auth.
    DATA profile TYPE ty_profile.

    "! the basic characteristic of a characteristic: whose hierarchies and copies it has
    CLASS-METHODS basic_of
      IMPORTING iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE rsiobjnm.
    "! the copy of the slice of a line's hierarchy valid at the date, initial if BW has none then
    CLASS-METHODS copy_of
      IMPORTING copies        TYPE REF TO zzxxmla1_cl_bw_hierarchy_copy
                !line         TYPE zzxxmla1_cl_bw_auth=>ty_hierarchy_line
                !date         TYPE d
      RETURNING VALUE(result) TYPE ty_copy.
    "! the request of the factors' tuples, or of members alone
    CLASS-METHODS request
      IMPORTING characteristics TYPE zzxxmla1_cl_bw_auth=>ty_characteristics
                factors         TYPE ty_factors OPTIONAL
                members         TYPE zzxxmla1_cl_bw_auth=>ty_tuple OPTIONAL
      RETURNING VALUE(result)   TYPE ty_request.
    "! the statement of the check: rows PHASE (1 a member, 2 a combination), M (the member's number) and REASON,
    "! the first refusal only; no row: allowed
    CLASS-METHODS check_statement
      IMPORTING profile       TYPE ty_profile
                request       TYPE ty_request
      RETURNING VALUE(result) TYPE ty_statement.
    "! a derived table of bound values, the parameters appended in their order; no rows: an empty table
    CLASS-METHODS values_sql
      IMPORTING columns       TYPE ty_columns
                !rows         TYPE ty_rows
      CHANGING  params        TYPE zzxxmla1_cl_sql=>ty_t_param
      RETURNING VALUE(result) TYPE string.
    "! the path rows of the copies the lines are expanded on, a UNION ALL over the characteristics' path tables
    CLASS-METHODS paths_sql
      IMPORTING !lines        TYPE ty_lines
      RETURNING VALUE(result) TYPE string.
    "! the condition that the key expression is in the flat range of alias f
    CLASS-METHODS range_condition
      IMPORTING !key          TYPE string
      RETURNING VALUE(result) TYPE string.
    "! BW's pattern (CP) as LIKE patterns with the escape character \
    CLASS-METHODS like
      IMPORTING pattern       TYPE csequence
      RETURNING VALUE(result) TYPE ty_like.
    CLASS-METHODS like_pattern
      IMPORTING pattern       TYPE csequence
      RETURNING VALUE(result) TYPE string.
    "! the answer of the statement's row (none: allowed)
    CLASS-METHODS answer
      IMPORTING !rows         TYPE zzxxmla1_cl_sql=>ty_t_row
                request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
    "! the check of a request: the provider's refusal, an unrestricted user, else the statement
    METHODS answered
      IMPORTING request       TYPE ty_request
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_check.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_sql IMPLEMENTATION.

  METHOD read.
    DATA(region) = zzxxmla1_cl_bw_auth=>read( user     = user
                                              provider = provider
                                              key_date = key_date
                                              today    = today
                                              expand   = abap_false ).
    DATA(profile) = VALUE ty_profile( ).
    IF region->provider_refusal( ) IS INITIAL AND region->unrestricted( ) = abap_false.
      DATA(base) = region->profile( ).
      profile-characteristics = base-characteristics.
      profile-flats = base-flats.
      DATA(copies) = NEW zzxxmla1_cl_bw_hierarchy_copy( ).
      " the tables of each characteristic a line names first: creating them is a DDIC activation that commits
      DATA(done) = VALUE zzxxmla1_cl_bw_auth=>ty_characteristics( ).
      LOOP AT base-hierarchies INTO DATA(line).
        IF NOT line_exists( done[ table_line = line-iobjnm ] ).
          copies->create_tables( basic_of( line-iobjnm ) ).
          APPEND line-iobjnm TO done.
        ENDIF.
      ENDLOOP.
      LOOP AT base-hierarchies INTO line.
        APPEND VALUE #( line       = line
                        key_copy   = copy_of( copies = copies line = line date = key_date )
                        value_copy = copy_of( copies = copies line = line date = line-date ) ) TO profile-lines.
      ENDLOOP.
    ENDIF.
    result = create( region = region profile = profile ).
  ENDMETHOD.

  METHOD create.
    result = NEW #( ).
    result->region = region.
    result->profile = profile.
  ENDMETHOD.

  METHOD basic_of.
    " a reference characteristic has the hierarchies of its basic one
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @iobjnm AND objvers = 'A' INTO @result.
    IF result IS INITIAL.
      result = iobjnm.
    ENDIF.
  ENDMETHOD.

  METHOD copy_of.
    DATA(basic) = basic_of( line-iobjnm ).
    SELECT SINGLE hieid FROM rshiedir
      WHERE objvers = 'A'
        AND iobjnm = @basic
        AND hienm = @line-hienm
        AND version = @line-version
        AND datefrom <= @date
        AND dateto >= @date
      INTO @DATA(hieid) ##NEEDED.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.
    DATA(hierarchy) = copies->current( characteristic = basic
                                       name           = line-hienm
                                       version        = line-version
                                       key_date       = date ).
    result = VALUE #( hiesid = hierarchy-hiesid sver = condense( CONV string( hierarchy-sver ) )
                      path = hierarchy-path_table ).
  ENDMETHOD.

  METHOD applying.
    result = region->applying( ).
  ENDMETHOD.

  METHOD check.
    result = check_product( VALUE #( ( selection ) ) ).
  ENDMETHOD.

  METHOD check_product.
    result = answered( request( characteristics = profile-characteristics factors = factors ) ).
  ENDMETHOD.

  METHOD check_members.
    result = answered( request( characteristics = profile-characteristics members = members ) ).
  ENDMETHOD.

  METHOD answered.
    result = region->provider_refusal( ).
    IF result IS NOT INITIAL.
      RETURN.
    ENDIF.
    result-status = zzxxmla1_cl_bw_auth=>c_status-allowed.
    IF region->unrestricted( ) = abap_true OR ( request-members IS INITIAL AND request-factors = 0 ).
      RETURN.
    ENDIF.
    DATA(statement) = check_statement( profile = profile request = request ).
    result = answer( rows    = zzxxmla1_cl_sql=>query( sql = statement-sql columns = 3 params = statement-params )
                     request = request ).
  ENDMETHOD.

  METHOD answer.
    result-status = zzxxmla1_cl_bw_auth=>c_status-allowed.
    IF rows IS INITIAL.
      RETURN.
    ENDIF.
    DATA(row) = rows[ 1 ].
    DATA(reason) = condense( row[ 3 ] ).
    DATA(number) = CONV i( row[ 2 ] ).
    DATA(member) = COND zzxxmla1_cl_bw_auth=>ty_member(
      WHEN number > 0 AND number <= lines( request-members ) THEN request-members[ number ]-member ).
    result = zzxxmla1_cl_bw_auth=>refusal( reason = reason member = member ).
  ENDMETHOD.

  METHOD request.
    IF lines( characteristics ) > c_max_characteristics.
      RAISE EXCEPTION TYPE zzxxmla1_cx_sql
        EXPORTING
          statement     = ``
          error_message = |olap4abap checks at most { c_max_characteristics } authorization-relevant | &&
                          |characteristics, the provider has { lines( characteristics ) }|.
    ENDIF.
    " the members in the order the query's tuples show them first, as ZZXXMLA1_CL_BW_AUTH's check meets them in the
    " product (the last factor fastest): tuple j of factor i first in the combination of the first tuples but j, whose
    " rank is (j - 1) times the number of combinations of the factors after i; then the members given alone
    TYPES: BEGIN OF ty_seen,
             rank     TYPE decfloat34,
             factor   TYPE i,
             position TYPE i,
             member   TYPE zzxxmla1_cl_bw_auth=>ty_member,
           END OF ty_seen.
    DATA seen TYPE STANDARD TABLE OF ty_seen WITH EMPTY KEY.
    LOOP AT factors INTO DATA(factor).
      DATA(i) = sy-tabix.
      DATA(after) = CONV decfloat34( 1 ).
      LOOP AT factors INTO DATA(later) FROM i + 1.
        after = after * lines( later ).
      ENDLOOP.
      LOOP AT factor INTO DATA(tuple).
        DATA(rank) = ( sy-tabix - 1 ) * after.
        LOOP AT tuple INTO DATA(member).
          APPEND VALUE #( rank = rank factor = i position = sy-tabix member = member ) TO seen.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
    SORT seen BY rank factor position.
    DATA(all) = VALUE zzxxmla1_cl_bw_auth=>ty_tuple( FOR s IN seen ( s-member ) ).
    APPEND LINES OF members TO all.
    LOOP AT all INTO member.
      IF NOT line_exists( characteristics[ table_line = member-iobjnm ] ).
        CONTINUE.
      ENDIF.
      IF NOT line_exists( result-members[ member = member ] ).
        APPEND VALUE #( member = member
                        key    = COND #( WHEN member-kind = zzxxmla1_cl_bw_auth=>c_kind-value AND member-value = `#`
                                         THEN `` ELSE member-value ) ) TO result-members.
      ENDIF.
    ENDLOOP.

    LOOP AT factors INTO factor.
      DATA(factor_number) = sy-tabix.
      IF factor IS INITIAL.
        " no tuple at all: nothing to combine
        CLEAR result-tuples.
        result-factors = 0.
        RETURN.
      ENDIF.
      result-factors = factor_number.
      LOOP AT factor INTO tuple.
        DATA(tuple_number) = sy-tabix.
        DATA(mask) = 0.
        DATA(numbers) = VALUE int4_table( ).
        LOOP AT tuple INTO member.
          READ TABLE characteristics TRANSPORTING NO FIELDS WITH KEY table_line = member-iobjnm.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.
          DATA(bit) = ipow( base = 2 exp = sy-tabix - 1 ).
          IF mask DIV bit MOD 2 = 0.
            mask = mask + bit.
          ENDIF.
          READ TABLE result-members TRANSPORTING NO FIELDS WITH KEY member = member.
          APPEND sy-tabix TO numbers.
        ENDLOOP.
        IF numbers IS INITIAL.
          APPEND 0 TO numbers.
        ENDIF.
        LOOP AT numbers INTO DATA(number).
          APPEND VALUE #( factor = factor_number tuple = tuple_number member = number mask = mask ) TO result-tuples.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD check_statement.
    DATA params TYPE zzxxmla1_cl_sql=>ty_t_param.
    DATA rows TYPE ty_rows.
    DATA(name) = `NVARCHAR( 30 )`.
    DATA(text) = `NVARCHAR( 250 )`.
    DATA(int) = `INTEGER`.

    " the request's members
    LOOP AT request-members INTO DATA(entry).
      APPEND VALUE #( ( NEW i( sy-tabix ) ) ( NEW string( entry-member-iobjnm ) ) ( NEW string( entry-member-kind ) )
                      ( NEW string( entry-key ) ) ( NEW string( entry-member-hienm ) )
                      ( NEW string( entry-member-version ) ) ( NEW string( entry-member-node_iobjnm ) )
                      ( NEW i( COND #( WHEN entry-member-named = abap_true THEN 1 ELSE 0 ) ) ) ) TO rows.
    ENDLOOP.
    DATA(members) = values_sql( EXPORTING columns = VALUE #( ( name = `M` type = int ) ( name = `IOBJ` type = name )
                                                             ( name = `KIND` type = `NVARCHAR( 1 )` )
                                                             ( name = `KEY` type = text ) ( name = `HIENM` type = name )
                                                             ( name = `VERSION` type = name )
                                                             ( name = `NODE_IOBJ` type = name )
                                                             ( name = `NAMED` type = int ) )
                                          rows    = rows
                                CHANGING  params  = params ).

    " the profile: per authorization and characteristic its flags and bit, its flat ranges, its hierarchy lines
    CLEAR rows.
    LOOP AT profile-flats INTO DATA(flat).
      DATA(bit) = ipow( base = 2 exp = line_index( profile-characteristics[ table_line = flat-iobjnm ] ) - 1 ).
      APPEND VALUE #( ( NEW string( flat-auth ) ) ( NEW string( flat-iobjnm ) )
                      ( NEW i( COND #( WHEN flat-all = abap_true THEN 1 ELSE 0 ) ) )
                      ( NEW i( COND #( WHEN flat-aggregate = abap_true OR flat-all = abap_true THEN 1 ELSE 0 ) ) )
                      ( NEW i( bit ) ) ) TO rows.
    ENDLOOP.
    DATA(parts) = values_sql( EXPORTING columns = VALUE #( ( name = `A` type = name ) ( name = `IOBJ` type = name )
                                                           ( name = `ALL` type = int ) ( name = `AGG` type = int )
                                                           ( name = `BIT` type = int ) )
                                        rows    = rows
                              CHANGING  params  = params ).
    CLEAR rows.
    LOOP AT profile-flats INTO flat WHERE all = abap_false.
      LOOP AT flat-ranges INTO DATA(range).
        DATA(pattern) = COND ty_like( WHEN range-option = 'CP' THEN like( range-low ) ).
        APPEND VALUE #( ( NEW string( flat-auth ) ) ( NEW string( flat-iobjnm ) ) ( NEW string( range-sign ) )
                        ( NEW string( range-option ) ) ( NEW string( range-low ) ) ( NEW string( range-high ) )
                        ( NEW string( pattern-pattern ) ) ( NEW string( pattern-number ) )
                        ( NEW string( pattern-rest ) ) ) TO rows.
      ENDLOOP.
    ENDLOOP.
    DATA(ranges) = values_sql( EXPORTING columns = VALUE #( ( name = `A` type = name ) ( name = `IOBJ` type = name )
                                                            ( name = `SIGN` type = `NVARCHAR( 1 )` )
                                                            ( name = `OPT` type = `NVARCHAR( 2 )` )
                                                            ( name = `LOW` type = text ) ( name = `HIGH` type = text )
                                                            ( name = `PAT` type = `NVARCHAR( 500 )` )
                                                            ( name = `NUM` type = text )
                                                            ( name = `REST` type = `NVARCHAR( 500 )` ) )
                                         rows    = rows
                               CHANGING  params  = params ).
    CLEAR rows.
    LOOP AT profile-lines INTO DATA(line).
      " the key date's copy always (also without one: the line still names its hierarchy), the line date's if any
      DO 2 TIMES.
        DATA(which) = COND string( WHEN sy-index = 1 THEN c_key_copy ELSE c_value_copy ).
        DATA(copy) = COND ty_copy( WHEN sy-index = 1 THEN line-key_copy ELSE line-value_copy ).
        IF sy-index = 2 AND copy-hiesid = 0.
          CONTINUE.
        ENDIF.
        APPEND VALUE #( ( NEW string( line-line-auth ) ) ( NEW string( line-line-iobjnm ) )
                        ( NEW string( line-line-hienm ) ) ( NEW string( line-line-version ) )
                        ( NEW string( line-line-node_iobjnm ) ) ( NEW string( line-line-node ) )
                        ( NEW string( line-line-type ) ) ( NEW i( line-line-level ) ) ( NEW string( which ) )
                        ( NEW i( copy-hiesid ) ) ( NEW string( copy-sver ) ) ) TO rows.
      ENDDO.
    ENDLOOP.
    DATA(hierarchy_lines) = values_sql( EXPORTING columns = VALUE #( ( name = `A` type = name )
                                                                     ( name = `IOBJ` type = name )
                                                                     ( name = `HIENM` type = name )
                                                                     ( name = `VERSION` type = name )
                                                                     ( name = `NODE_IOBJ` type = name )
                                                                     ( name = `NODE` type = text )
                                                                     ( name = `TYPE` type = `NVARCHAR( 1 )` )
                                                                     ( name = `LVL` type = int )
                                                                     ( name = `WHICH` type = `NVARCHAR( 1 )` )
                                                                     ( name = `HIESID` type = int )
                                                                     ( name = `SVER` type = `NVARCHAR( 10 )` ) )
                                                  rows    = rows
                                        CHANGING  params  = params ).

    " what each line shows: the occurrences of its node by type, each by its own row; a leaf (OWN_SID from 0) is a
    " value it authorizes
    DATA(cover) =
      |SELECT DISTINCT h."A", h."IOBJ", h."HIENM", h."VERSION", h."WHICH", o."NODE_IOBJ", o."NODE_NAME" AS "NODE", | &&
      |CASE WHEN o."OWN_SID" >= 0 THEN 1 ELSE 0 END AS "LEAF" FROM q_h AS h | &&
      |INNER JOIN q_x AS s ON s."IOBJ" = h."IOBJ" AND s."HIESID" = h."HIESID" AND s."SVER" = h."SVER" | &&
      |INNER JOIN q_x AS o ON o."IOBJ" = s."IOBJ" AND o."HIESID" = s."HIESID" AND o."SVER" = s."SVER" | &&
      |AND o."POS" = s."POS" AND o."TLEVEL" = o."DEPTH" | &&
      |WHERE ( h."TYPE" IN ( '3', '4' ) AND s."TLEVEL" = 1 ) | &&
      |OR ( h."TYPE" NOT IN ( '3', '4' ) AND s."NODE_IOBJ" = h."NODE_IOBJ" AND s."NODE_NAME" = h."NODE" | &&
      |AND ( h."TYPE" <> '0' OR s."TLEVEL" = s."DEPTH" ) | &&
      |AND ( h."TYPE" <> '2' OR s."DEPTH" <= h."LVL" OR s."TLEVEL" = s."DEPTH" ) )|.

    " the authorizations that admit a member: all values, the aggregate, a value in an including range or among a
    " line's leaves and in no excluding range, a node a line shows of its hierarchy
    DATA(admitted) =
      |SELECT m."M", p."A" FROM q_m AS m INNER JOIN q_p AS p ON p."IOBJ" = m."IOBJ" | &&
      |WHERE p."ALL" = 1 | &&
      |OR ( m."KIND" = 'A' AND p."AGG" = 1 ) | &&
      |OR ( m."KIND" = 'V' AND ( EXISTS ( SELECT 1 FROM q_f AS f WHERE f."A" = p."A" AND f."IOBJ" = m."IOBJ" | &&
      |AND f."SIGN" = 'I' AND { range_condition( `m."KEY"` ) } ) | &&
      |OR EXISTS ( SELECT 1 FROM q_c AS c WHERE c."A" = p."A" AND c."IOBJ" = m."IOBJ" AND c."WHICH" = 'V' | &&
      |AND c."LEAF" = 1 AND c."NODE" = m."KEY" ) ) | &&
      |AND NOT EXISTS ( SELECT 1 FROM q_f AS f WHERE f."A" = p."A" AND f."IOBJ" = m."IOBJ" AND f."SIGN" = 'E' | &&
      |AND { range_condition( `m."KEY"` ) } ) ) | &&
      |OR ( m."KIND" = 'N' AND EXISTS ( SELECT 1 FROM q_c AS c WHERE c."A" = p."A" AND c."IOBJ" = m."IOBJ" | &&
      |AND c."WHICH" = 'K' AND c."HIENM" = m."HIENM" AND c."VERSION" = m."VERSION" | &&
      |AND c."NODE_IOBJ" = m."NODE_IOBJ" AND c."NODE" = m."KEY" ) )|.

    " the first member no authorization admits, the named ones first, with BW's reason
    DATA(refused_member) =
      |SELECT 1 AS "PHASE", m."M", CASE WHEN m."KIND" = 'V' THEN CASE | &&
      |WHEN NOT EXISTS ( SELECT 1 FROM q_p AS p WHERE p."IOBJ" = m."IOBJ" AND p."ALL" = 1 ) | &&
      |AND NOT EXISTS ( SELECT 1 FROM q_f AS f WHERE f."IOBJ" = m."IOBJ" ) | &&
      |AND NOT EXISTS ( SELECT 1 FROM q_c AS c WHERE c."IOBJ" = m."IOBJ" AND c."WHICH" = 'V' AND c."LEAF" = 1 ) | &&
      |THEN '{ zzxxmla1_cl_bw_auth=>c_reason-no_values }' WHEN m."NAMED" = 1 THEN '{ zzxxmla1_cl_bw_auth=>c_reason-value }' | &&
      |ELSE '{ zzxxmla1_cl_bw_auth=>c_reason-combination }' END | &&
      |WHEN EXISTS ( SELECT 1 FROM q_h AS h WHERE h."IOBJ" = m."IOBJ" AND h."HIENM" = m."HIENM" | &&
      |AND h."VERSION" = m."VERSION" ) THEN '{ zzxxmla1_cl_bw_auth=>c_reason-node }' | &&
      |ELSE '{ zzxxmla1_cl_bw_auth=>c_reason-hierarchy }' END AS "REASON" | &&
      |FROM q_m AS m WHERE m."KIND" <> 'A' AND NOT EXISTS ( SELECT 1 FROM q_o AS o WHERE o."M" = m."M" ) | &&
      |ORDER BY m."NAMED" DESC, m."M" LIMIT 1|.

    DATA(ctes) = VALUE string_table(
      ( |q_m AS ( { members } )| ) ( |q_p AS ( { parts } )| ) ( |q_f AS ( { ranges } )| )
      ( |q_h AS ( { hierarchy_lines } )| ) ( |q_x AS ( { paths_sql( profile-lines ) } )| )
      ( |q_c AS ( { cover } )| ) ( |q_o AS ( { admitted } )| )
      ( |q_a AS ( SELECT "A", SUM( CASE WHEN "AGG" = 1 THEN "BIT" ELSE 0 END ) AS "AGG" FROM q_p GROUP BY "A" )| ) ).
    DATA(branches) = VALUE string_table( ( |SELECT * FROM ( { refused_member } ) AS r1| ) ).

    " a combination of one tuple per factor that no authorization allows: each tuple's members admitted, the
    " characteristics no tuple has aggregated
    IF request-factors > 0.
      DATA(sources) = VALUE string_table( ).
      DATA(conditions) = VALUE string_table( ).
      DATA(joins) = ``.
      DATA(mask) = ``.
      DO request-factors TIMES.
        DATA(i) = sy-index.
        CLEAR rows.
        LOOP AT request-tuples INTO DATA(tuple) WHERE factor = i.
          APPEND VALUE #( ( NEW i( tuple-tuple ) ) ( NEW i( tuple-member ) ) ( NEW i( tuple-mask ) ) ) TO rows.
        ENDLOOP.
        DATA(tuples) = values_sql( EXPORTING columns = VALUE #( ( name = `T` type = int ) ( name = `M` type = int )
                                                                ( name = `MASK` type = int ) )
                                             rows    = rows
                                   CHANGING  params  = params ).
        APPEND |q_t{ i } AS ( { tuples } )| TO ctes.
        APPEND |q_k{ i } AS ( SELECT x."T", a."A" FROM ( SELECT DISTINCT "T" FROM q_t{ i } ) AS x CROSS JOIN q_a AS a | &&
               |WHERE NOT EXISTS ( SELECT 1 FROM q_t{ i } AS y WHERE y."T" = x."T" AND y."M" <> 0 | &&
               |AND NOT EXISTS ( SELECT 1 FROM q_o AS o WHERE o."M" = y."M" AND o."A" = a."A" ) ) )| TO ctes.
        APPEND |( SELECT DISTINCT "T", "MASK" FROM q_t{ i } ) AS c{ i }| TO sources.
        joins = |{ joins } INNER JOIN q_k{ i } AS k{ i } ON k{ i }."A" = a."A"|.
        APPEND |k{ i }."T" = c{ i }."T"| TO conditions.
        mask = COND #( WHEN i = 1 THEN |c1."MASK"| ELSE |BITOR( { mask }, c{ i }."MASK" )| ).
      ENDDO.
      DATA(every) = ipow( base = 2 exp = lines( profile-characteristics ) ) - 1.
      APPEND |BITAND( CAST( { every } - { mask } AS BIGINT ), CAST( { every } - a."AGG" AS BIGINT ) ) = 0| TO conditions.
      APPEND |SELECT * FROM ( SELECT 2 AS "PHASE", 0 AS "M", '{ zzxxmla1_cl_bw_auth=>c_reason-combination }' AS "REASON" | &&
             |FROM { concat_lines_of( table = sources sep = ` CROSS JOIN ` ) } | &&
             |WHERE NOT EXISTS ( SELECT 1 FROM q_a AS a{ joins } | &&
             |WHERE { concat_lines_of( table = conditions sep = ` AND ` ) } ) LIMIT 1 ) AS r2| TO branches.
    ENDIF.

    result-sql = |WITH { concat_lines_of( table = ctes sep = `, ` ) } | &&
                 |SELECT "PHASE", "M", "REASON" FROM ( { concat_lines_of( table = branches sep = ` UNION ALL ` ) } ) AS r | &&
                 |ORDER BY "PHASE" LIMIT 1|.
    result-params = params.
  ENDMETHOD.

  METHOD values_sql.
    IF rows IS INITIAL.
      result = |SELECT { concat_lines_of( table = VALUE string_table( FOR c IN columns
                                                    ( |CAST( NULL AS { c-type } ) AS "{ c-name }"| ) ) sep = `, ` ) } | &&
               |FROM DUMMY WHERE 1 = 0|.
      RETURN.
    ENDIF.
    DATA(row_sql) = |SELECT { concat_lines_of( table = VALUE string_table( FOR c IN columns
                                                 ( |CAST( ? AS { c-type } ) AS "{ c-name }"| ) ) sep = `, ` ) } FROM DUMMY|.
    DATA(selects) = VALUE string_table( ).
    LOOP AT rows INTO DATA(row).
      APPEND row_sql TO selects.
      APPEND LINES OF row TO params.
    ENDLOOP.
    result = concat_lines_of( table = selects sep = ` UNION ALL ` ).
  ENDMETHOD.

  METHOD paths_sql.
    " per characteristic its path table, the rows of the copies the lines read
    DATA selects TYPE string_table.
    LOOP AT lines INTO DATA(entry) GROUP BY entry-line-iobjnm INTO DATA(group).
      DATA(table) = VALUE tabname( ).
      DATA(keys) = VALUE string_table( ).
      LOOP AT GROUP group INTO DATA(member).
        DATA(both) = VALUE ty_copies( ( member-key_copy ) ( member-value_copy ) ).
        LOOP AT both INTO DATA(copy) WHERE hiesid <> 0.
          table = copy-path.
          DATA(key) = |( x."HIESID" = { copy-hiesid } AND x."SVER" = { zzxxmla1_cl_sql=>literal( copy-sver ) } )|.
          IF NOT line_exists( keys[ table_line = key ] ).
            APPEND key TO keys.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
      IF table IS INITIAL.
        CONTINUE.
      ENDIF.
      APPEND |SELECT { zzxxmla1_cl_sql=>literal( CONV string( group ) ) } AS "IOBJ", x."HIESID", x."SVER", x."POS", | &&
             |x."TLEVEL", x."DEPTH", x."OWN_SID", x."NODE_IOBJ", x."NODE_NAME" FROM { zzxxmla1_cl_sql=>quote( table ) } | &&
             |AS x WHERE { concat_lines_of( table = keys sep = ` OR ` ) }| TO selects.
    ENDLOOP.
    IF selects IS INITIAL.
      result = |SELECT CAST( NULL AS NVARCHAR( 30 ) ) AS "IOBJ", CAST( NULL AS INTEGER ) AS "HIESID", | &&
               |CAST( NULL AS NVARCHAR( 10 ) ) AS "SVER", CAST( NULL AS INTEGER ) AS "POS", | &&
               |CAST( NULL AS INTEGER ) AS "TLEVEL", CAST( NULL AS INTEGER ) AS "DEPTH", | &&
               |CAST( NULL AS INTEGER ) AS "OWN_SID", CAST( NULL AS NVARCHAR( 30 ) ) AS "NODE_IOBJ", | &&
               |CAST( NULL AS NVARCHAR( 250 ) ) AS "NODE_NAME" FROM DUMMY WHERE 1 = 0|.
      RETURN.
    ENDIF.
    result = concat_lines_of( table = selects sep = ` UNION ALL ` ).
  ENDMETHOD.

  METHOD range_condition.
    result = |( ( f."OPT" = 'EQ' AND { key } = f."LOW" ) | &&
             |OR ( f."OPT" = 'BT' AND { key } >= f."LOW" AND { key } <= f."HIGH" ) | &&
             |OR ( f."OPT" = 'CP' AND ( { key } LIKE f."PAT" ESCAPE '\\' | &&
             |OR ( f."NUM" <> '' AND LENGTH( { key } ) > LENGTH( f."NUM" ) AND { key } LIKE_REGEXPR '^[0-9]+$' | &&
             |AND { key } LIKE LPAD( f."NUM", LENGTH( { key } ), '0' ) \|\| f."REST" ESCAPE '\\' ) ) ) )|.
  ENDMETHOD.

  METHOD like.
    result-pattern = like_pattern( pattern ).
    DATA(digits) = find( val = pattern regex = `[^0-9]` ).
    IF digits > 0.
      result-number = substring( val = pattern len = digits ).
      result-rest = like_pattern( substring( val = pattern off = digits ) ).
    ENDIF.
  ENDMETHOD.

  METHOD like_pattern.
    DATA(offset) = 0.
    WHILE offset < strlen( pattern ).
      DATA(char) = substring( val = pattern off = offset len = 1 ).
      result = result && SWITCH string( char
                                        WHEN `*` THEN `%`
                                        WHEN `+` THEN `_`
                                        WHEN `%` OR `_` OR `\` THEN `\` && char
                                        ELSE char ).
      offset = offset + 1.
    ENDWHILE.
  ENDMETHOD.

ENDCLASS.
