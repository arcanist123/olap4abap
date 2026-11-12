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
"! The ABAP API of the authorization check (ZZXXMLA1_IF_BW_AUTH_CHECK; docs/next-steps.md, Now: analysis
"! authorisations, The check for other callers), over the check in HANA (ZZXXMLA1_CL_BW_AUTH_SQL).
"! for( ) reads the user's profile on the provider once and numbers the applying authorizations, a bit each (at most
"! 63); check( ) asks one statement per request: per member the authorizations that admit it, a bit mask per member.
"! An authorization is a sub-cube, so the product is authorized exactly when every combination of one member per
"! characteristic has a common authorization. Members of a characteristic with the same mask are interchangeable, a
"! class; the combinations of classes are searched depth first with the AND of their masks, a combination whose AND
"! is 0 an uncovered sub-product (a hole), the rest of the product below it not searched. A member with mask 0 is in
"! no authorization: refused with BW's reason. Neither the product nor the authorized space is built.
CLASS zzxxmla1_cl_bw_auth_check DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    INTERFACES zzxxmla1_if_bw_auth_check.

    "! The authorizations an applying authorization is numbered among: a bit each in a mask of 8 bytes, the sign bit
    "! left out as in a BIGINT (decided with the user 2026-11-12).
    CONSTANTS c_max_auths TYPE i VALUE 63.

    "! The check of the user on the InfoProvider (InfoCube or aDSO, BW's name) at the key date. Reading the profile
    "! can create the copy tables of a characteristic (a DDIC activation that commits) and refill copies: do not call
    "! it inside an update LUW of the caller.
    "! @raising zzxxmla1_cx_bw_auth_check | the provider does not exist, or more than c_max_auths authorizations apply
    CLASS-METHODS for
      IMPORTING !user         TYPE xubname
                provider      TYPE csequence
                key_date      TYPE d DEFAULT '99991231'
      RETURNING VALUE(result) TYPE REF TO zzxxmla1_if_bw_auth_check
      RAISING   zzxxmla1_cx_bw_auth_check.

  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES ty_mask TYPE x LENGTH 8.
    "! a member of the request with the mask of the authorizations that admit it and, with mask 0, its refusal
    TYPES: BEGIN OF ty_entry,
             member  TYPE zzxxmla1_if_bw_auth_check=>ty_member,
             mask    TYPE ty_mask,
             refusal TYPE zzxxmla1_if_bw_auth_check=>ty_refused,
           END OF ty_entry.
    TYPES ty_entries TYPE STANDARD TABLE OF ty_entry WITH EMPTY KEY.
    "! the members of one characteristic, in the order of the request
    TYPES: BEGIN OF ty_group,
             characteristic TYPE rsiobjnm,
             entries        TYPE ty_entries,
           END OF ty_group.
    TYPES ty_groups TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.
    "! the members of a characteristic with one mask
    TYPES: BEGIN OF ty_class,
             mask    TYPE ty_mask,
             members TYPE zzxxmla1_if_bw_auth_check=>ty_members,
           END OF ty_class.
    TYPES ty_classes TYPE STANDARD TABLE OF ty_class WITH EMPTY KEY.
    TYPES ty_dimensions TYPE STANDARD TABLE OF ty_classes WITH EMPTY KEY.
    TYPES ty_auth_numbers TYPE SORTED TABLE OF rsauth WITH UNIQUE KEY table_line.
    TYPES ty_names TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.

    DATA sql TYPE REF TO zzxxmla1_cl_bw_auth_sql.
    DATA key_date TYPE d.
    "! the provider's characteristics, its authorization-relevant ones and the applying authorizations by number
    DATA provider_characteristics TYPE ty_names.
    DATA relevant TYPE ty_names.
    DATA auths TYPE ty_auth_numbers.

    "! the request's members grouped by characteristic in the order of the request, each once, normalized (kind upper
    "! case, # for the not-assigned value, : for the aggregate)
    CLASS-METHODS groups_of
      IMPORTING request       TYPE zzxxmla1_if_bw_auth_check=>ty_members
      RETURNING VALUE(result) TYPE ty_groups.
    "! the member as the check in HANA takes it: a leaf as a node whose InfoObject is the characteristic
    CLASS-METHODS internal
      IMPORTING !member       TYPE zzxxmla1_if_bw_auth_check=>ty_member
      RETURNING VALUE(result) TYPE zzxxmla1_cl_bw_auth=>ty_member.
    "! the name of a node or leaf in BW's hierarchy table and the copies: a leaf's # is the not-assigned value, whose
    "! key is blank
    CLASS-METHODS leaf_key
      IMPORTING !member       TYPE zzxxmla1_if_bw_auth_check=>ty_member
      RETURNING VALUE(result) TYPE string.
    "! the answer of the masks: the refused members, the holes of the classes, the status of the first refusal
    CLASS-METHODS decide
      IMPORTING !groups       TYPE ty_groups
      RETURNING VALUE(result) TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the holes below a combination of classes of the dimensions before depth whose masks AND to mask
    CLASS-METHODS collect_holes
      IMPORTING dimensions TYPE ty_dimensions
                !depth     TYPE i
                !mask      TYPE ty_mask
                chosen     TYPE zzxxmla1_if_bw_auth_check=>ty_members
      CHANGING  answer     TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! an answer of status ERROR
    CLASS-METHODS error
      IMPORTING reason        TYPE csequence
                !message      TYPE csequence
      RETURNING VALUE(result) TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the basic characteristic: whose hierarchies and SID table it has
    CLASS-METHODS basic_of
      IMPORTING iobjnm        TYPE rsiobjnm
      RETURNING VALUE(result) TYPE rsiobjnm.
    "! the error of a request that is not well formed or misses an authorization-relevant characteristic; initial if
    "! none
    METHODS request_error
      IMPORTING !groups       TYPE ty_groups
      RETURNING VALUE(result) TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the error of the first hierarchy without a slice at the key date, node, leaf or value the provider does not
    "! have; initial if none
    METHODS existence_error
      IMPORTING !groups       TYPE ty_groups
      RETURNING VALUE(result) TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the error of the first node or leaf of the hierarchy not in its slice at the key date; initial if none
    METHODS node_error
      IMPORTING characteristic TYPE rsiobjnm
                hierarchy      TYPE rshienm
                !version       TYPE rsversion
                !members       TYPE zzxxmla1_if_bw_auth_check=>ty_members
      RETURNING VALUE(result)  TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the error of the first flat value of the characteristic without a SID; initial if none or if its SID table
    "! cannot be read by the key alone (a compounded characteristic)
    METHODS value_error
      IMPORTING characteristic TYPE rsiobjnm
                !members       TYPE zzxxmla1_if_bw_auth_check=>ty_members
      RETURNING VALUE(result)  TYPE zzxxmla1_if_bw_auth_check=>ty_answer.
    "! the masks of the members by the statement of the check in HANA, the refusal of those with mask 0
    METHODS admit
      CHANGING !groups TYPE ty_groups.
ENDCLASS.



CLASS zzxxmla1_cl_bw_auth_check IMPLEMENTATION.

  METHOD for.
    DATA(check) = NEW zzxxmla1_cl_bw_auth_check( ).
    check->key_date = key_date.
    TRY.
        check->provider_characteristics = NEW zzxxmla1_cl_bw_provider( )->characteristic_names( provider ).
        check->sql = zzxxmla1_cl_bw_auth_sql=>read( user = user provider = provider key_date = key_date ).
      CATCH zzxxmla1_cx_bw_provider INTO DATA(provider_error).
        RAISE EXCEPTION TYPE zzxxmla1_cx_bw_auth_check
          EXPORTING error_message = provider_error->get_text( )
                    previous      = provider_error.
    ENDTRY.
    check->relevant = check->sql->characteristics( ).
    LOOP AT check->sql->applying( ) INTO DATA(auth).
      INSERT auth INTO TABLE check->auths.
    ENDLOOP.
    IF lines( check->auths ) > c_max_auths AND check->sql->unrestricted( ) = abap_false
       AND check->sql->provider_refusal( ) IS INITIAL.
      RAISE EXCEPTION TYPE zzxxmla1_cx_bw_auth_check
        EXPORTING error_message = |{ lines( check->auths ) } analysis authorizations of { user } apply to { provider
                                  }; olap4abap checks at most { c_max_auths }|.
    ENDIF.
    result = check.
  ENDMETHOD.

  METHOD zzxxmla1_if_bw_auth_check~characteristics.
    result = relevant.
  ENDMETHOD.

  METHOD zzxxmla1_if_bw_auth_check~applying.
    result = VALUE #( FOR a IN auths ( a ) ).
  ENDMETHOD.

  METHOD zzxxmla1_if_bw_auth_check~check.
    LOOP AT request INTO DATA(member).
      IF NOT line_exists( provider_characteristics[ table_line = member-characteristic ] ).
        RAISE EXCEPTION TYPE zzxxmla1_cx_bw_auth_check
          EXPORTING error_message = |The provider has no characteristic { member-characteristic }|.
      ENDIF.
    ENDLOOP.
    DATA(groups) = groups_of( request ).
    result = request_error( groups ).
    IF result IS NOT INITIAL.
      RETURN.
    ENDIF.
    " the characteristics that are not authorization relevant are not checked
    LOOP AT groups INTO DATA(group).
      IF NOT line_exists( relevant[ table_line = group-characteristic ] ).
        DELETE groups.
      ENDIF.
    ENDLOOP.
    result = existence_error( groups ).
    IF result IS NOT INITIAL.
      RETURN.
    ENDIF.
    DATA(refusal) = sql->provider_refusal( ).
    IF refusal IS NOT INITIAL.
      result = VALUE #( status = refusal-status reason = refusal-reason message = refusal-message ).
      RETURN.
    ENDIF.
    IF sql->unrestricted( ) = abap_true OR groups IS INITIAL.
      result-status = zzxxmla1_if_bw_auth_check=>c_status-allowed.
      RETURN.
    ENDIF.
    admit( CHANGING groups = groups ).
    result = decide( groups ).
  ENDMETHOD.

  METHOD groups_of.
    LOOP AT request INTO DATA(member).
      TRANSLATE member-kind TO UPPER CASE.
      CASE member-kind.
        WHEN zzxxmla1_if_bw_auth_check=>c_kind-aggregate.
          " the target of VALUE is cleared before its components are read: only the fields an aggregate keeps
          CLEAR: member-hierarchy, member-version, member-node_iobjnm.
          member-value = zzxxmla1_if_bw_auth_check=>c_aggregate.
        WHEN zzxxmla1_if_bw_auth_check=>c_kind-value.
          IF member-value IS INITIAL.
            member-value = `#`.
          ENDIF.
          IF member-hierarchy IS INITIAL.
            CLEAR: member-version, member-node_iobjnm.
          ELSE.
            member-node_iobjnm = member-characteristic.
          ENDIF.
      ENDCASE.
      READ TABLE result ASSIGNING FIELD-SYMBOL(<group>) WITH KEY characteristic = member-characteristic.
      IF sy-subrc <> 0.
        APPEND VALUE #( characteristic = member-characteristic ) TO result ASSIGNING <group>.
      ENDIF.
      IF NOT line_exists( <group>-entries[ member = member ] ).
        APPEND VALUE #( member = member ) TO <group>-entries.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD request_error.
    LOOP AT groups INTO DATA(group).
      LOOP AT group-entries INTO DATA(entry).
        DATA(member) = entry-member.
        IF member-kind <> zzxxmla1_if_bw_auth_check=>c_kind-value AND member-kind <> zzxxmla1_if_bw_auth_check=>c_kind-node
           AND member-kind <> zzxxmla1_if_bw_auth_check=>c_kind-aggregate.
          result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-request
                          message = |Member { member-value } of { member-characteristic } has kind { member-kind
                                    }, not V, N or A| ).
          RETURN.
        ENDIF.
        IF member-kind = zzxxmla1_if_bw_auth_check=>c_kind-node
           AND ( member-hierarchy IS INITIAL OR member-node_iobjnm IS INITIAL OR member-value IS INITIAL ).
          result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-request
                          message = |Node { member-value } of { member-characteristic } needs its name, hierarchy | &&
                                    |and InfoObject| ).
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
    LOOP AT relevant INTO DATA(characteristic).
      IF NOT line_exists( groups[ characteristic = characteristic ] ).
        result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-missing
                        message = |The request names no member of the authorization-relevant characteristic { characteristic
                                  }; ask the aggregate (kind A) for its total| ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD existence_error.
    TYPES: BEGIN OF ty_hierarchy,
             hierarchy TYPE rshienm,
             version   TYPE rsversion,
           END OF ty_hierarchy.
    DATA hierarchies TYPE STANDARD TABLE OF ty_hierarchy WITH EMPTY KEY.
    LOOP AT groups INTO DATA(group).
      DATA(basic) = basic_of( group-characteristic ).
      CLEAR hierarchies.
      LOOP AT group-entries INTO DATA(entry) WHERE member-hierarchy IS NOT INITIAL.
        DATA(hierarchy) = VALUE ty_hierarchy( hierarchy = entry-member-hierarchy version = entry-member-version ).
        IF NOT line_exists( hierarchies[ table_line = hierarchy ] ).
          APPEND hierarchy TO hierarchies.
        ENDIF.
      ENDLOOP.
      LOOP AT hierarchies INTO hierarchy.
        IF zzxxmla1_cl_bw_hierarchy_copy=>has_slice( characteristic = basic
                                                       name           = hierarchy-hierarchy
                                                       version        = hierarchy-version
                                                       key_date       = key_date ) = abap_false.
          result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-hierarchy
                          message = |Hierarchy { hierarchy-hierarchy } { hierarchy-version } of { group-characteristic
                                    } has no slice at { key_date DATE = ISO }| ).
          RETURN.
        ENDIF.
        result = node_error( characteristic = group-characteristic
                             hierarchy      = hierarchy-hierarchy
                             version        = hierarchy-version
                             members        = VALUE #( FOR e IN group-entries
                                                       WHERE ( member-hierarchy = hierarchy-hierarchy
                                                               AND member-version = hierarchy-version )
                                                       ( e-member ) ) ).
        IF result IS NOT INITIAL.
          RETURN.
        ENDIF.
      ENDLOOP.
      result = value_error( characteristic = group-characteristic
                            members        = VALUE #( FOR e IN group-entries
                                                      WHERE ( member-kind = zzxxmla1_if_bw_auth_check=>c_kind-value
                                                              AND member-hierarchy IS INITIAL
                                                              AND member-value <> `#` )
                                                      ( e-member ) ) ).
      IF result IS NOT INITIAL.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD node_error.
    DATA hietab TYPE rshietab.
    DATA hintab TYPE rshintab.
    DATA names TYPE RANGE OF rsshnodenamestr.
    DATA found TYPE STANDARD TABLE OF rsshnodenamestr WITH EMPTY KEY.
    DATA(basic) = basic_of( characteristic ).
    SELECT SINGLE hieid FROM rshiedir
      WHERE objvers = 'A'
        AND iobjnm = @basic
        AND hienm = @hierarchy
        AND version = @version
        AND datefrom <= @key_date
        AND dateto >= @key_date
      INTO @DATA(hieid).
    CALL FUNCTION 'RSD_HIETAB_GET_FOR_CHA_BAS'
      EXPORTING
        i_chabasnm = basic
      IMPORTING
        e_hietab   = hietab
        e_hintab   = hintab
      EXCEPTIONS
        name_error = 1
        OTHERS     = 2.
    IF sy-subrc <> 0 OR hietab IS INITIAL.
      RETURN.
    ENDIF.
    LOOP AT members INTO DATA(member) GROUP BY member-node_iobjnm INTO DATA(node_iobjnm).
      names = VALUE #( FOR m IN GROUP node_iobjnm ( sign = 'I' option = 'EQ' low = leaf_key( m ) ) ).
      SELECT nodename
        FROM (hietab)
        WHERE hieid = @hieid
          AND objvers = 'A'
          AND iobjnm = @node_iobjnm
          AND nodename IN @names
        INTO TABLE @found.
      LOOP AT GROUP node_iobjnm INTO member.
        IF NOT line_exists( found[ table_line = leaf_key( member ) ] ).
          result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-member
                          message = |{ COND string( WHEN member-kind = zzxxmla1_if_bw_auth_check=>c_kind-node
                                                    THEN |Node { member-value } { member-node_iobjnm }|
                                                    ELSE |Leaf { member-value }| ) } is not in hierarchy { hierarchy
                                    } { version } of { characteristic } at { key_date DATE = ISO }| ).
          RETURN.
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD value_error.
    DATA keys TYPE RANGE OF rschavl.
    DATA found TYPE STANDARD TABLE OF rschavl WITH EMPTY KEY.
    IF members IS INITIAL.
      RETURN.
    ENDIF.
    DATA(basic) = condense( CONV string( basic_of( characteristic ) ) ).
    DATA(sap) = xsdbool( substring( val = basic len = 1 ) = `0` ).
    DATA(table) = COND string( WHEN sap = abap_true THEN |/BI0/S{ substring( val = basic off = 1 ) }|
                               ELSE |/BIC/S{ basic }| ).
    DATA(column) = COND string( WHEN sap = abap_true THEN substring( val = basic off = 1 ) ELSE |/BIC/{ basic }| ).
    DATA(where) = |{ column } IN @keys|.
    " a compounded characteristic's SID table has more key fields than SID and the key: not checked by the key alone
    SELECT COUNT(*) FROM dd03l
      WHERE tabname = @table
        AND as4local = 'A'
        AND keyflag = 'X'
        AND fieldname <> 'MANDT'
      INTO @DATA(key_fields).
    IF key_fields <> 1.
      RETURN.
    ENDIF.
    keys = VALUE #( FOR m IN members ( sign = 'I' option = 'EQ' low = m-value ) ).
    TRY.
        SELECT (column)
          FROM (table)
          WHERE (where)
          INTO TABLE @found.
      CATCH cx_sy_dynamic_osql_error.
        RETURN.
    ENDTRY.
    LOOP AT members INTO DATA(member).
      IF NOT line_exists( found[ table_line = member-value ] ).
        result = error( reason  = zzxxmla1_if_bw_auth_check=>c_error-member
                        message = |Value { member-value } of { characteristic } does not exist| ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD admit.
    DATA members TYPE zzxxmla1_cl_bw_auth=>ty_tuple.
    DATA reason TYPE c LENGTH 12.
    LOOP AT groups INTO DATA(group).
      LOOP AT group-entries INTO DATA(entry).
        APPEND internal( entry-member ) TO members.
      ENDLOOP.
    ENDLOOP.
    DATA(admissions) = sql->admissions( members ).
    LOOP AT groups ASSIGNING FIELD-SYMBOL(<group>).
      LOOP AT <group>-entries ASSIGNING FIELD-SYMBOL(<entry>).
        DATA(member) = internal( <entry>-member ).
        CLEAR reason.
        LOOP AT admissions INTO DATA(admission) WHERE member = member.
          IF admission-auth IS INITIAL.
            reason = admission-reason.
          ELSE.
            DATA(bit) = line_index( auths[ table_line = admission-auth ] ).
            IF bit > 0.
              SET BIT bit OF <entry>-mask.
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF <entry>-mask IS INITIAL.
          DATA(check) = zzxxmla1_cl_bw_auth=>refusal(
                          reason = COND string( WHEN reason IS NOT INITIAL THEN reason
                                                ELSE zzxxmla1_cl_bw_auth=>c_reason-combination )
                          member = member ).
          <entry>-refusal = VALUE #( member = <entry>-member status = check-status reason = check-reason
                                     message = check-message ).
        ENDIF.
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.

  METHOD internal.
    result = VALUE #( iobjnm = member-characteristic kind = member-kind value = member-value
                      hienm = member-hierarchy version = member-version node_iobjnm = member-node_iobjnm
                      named = abap_true ).
    CASE member-kind.
      WHEN zzxxmla1_if_bw_auth_check=>c_kind-aggregate.
        CLEAR result-value.
      WHEN zzxxmla1_if_bw_auth_check=>c_kind-value.
        IF member-hierarchy IS NOT INITIAL.
          " a leaf: a node whose InfoObject is the characteristic, named by its key
          result-kind = zzxxmla1_cl_bw_auth=>c_kind-node.
          result-node_iobjnm = member-characteristic.
          result-value = leaf_key( member ).
        ENDIF.
    ENDCASE.
  ENDMETHOD.

  METHOD leaf_key.
    result = member-value.
    IF member-kind = zzxxmla1_if_bw_auth_check=>c_kind-value AND member-value = `#`.
      CLEAR result.
    ENDIF.
  ENDMETHOD.

  METHOD decide.
    " a refused member with the first combination of the product that shows it (the last characteristic fastest):
    " member i of characteristic k first in combination (i - 1) times the combinations of the characteristics after k
    TYPES: BEGIN OF ty_ranked,
             rank     TYPE decfloat34,
             position TYPE i,
             refusal  TYPE zzxxmla1_if_bw_auth_check=>ty_refused,
           END OF ty_ranked.
    DATA ranked TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.
    DATA dimensions TYPE ty_dimensions.
    result-status = zzxxmla1_if_bw_auth_check=>c_status-allowed.
    LOOP AT groups INTO DATA(group).
      DATA(position) = sy-tabix.
      DATA(after) = CONV decfloat34( 1 ).
      LOOP AT groups INTO DATA(later) FROM position + 1.
        after = after * lines( later-entries ).
      ENDLOOP.
      DATA(classes) = VALUE ty_classes( ).
      LOOP AT group-entries INTO DATA(entry).
        IF entry-mask IS INITIAL.
          APPEND VALUE #( rank = ( sy-tabix - 1 ) * after position = position refusal = entry-refusal ) TO ranked.
          CONTINUE.
        ENDIF.
        READ TABLE classes ASSIGNING FIELD-SYMBOL(<class>) WITH KEY mask = entry-mask.
        IF sy-subrc <> 0.
          APPEND VALUE #( mask = entry-mask ) TO classes ASSIGNING <class>.
        ENDIF.
        APPEND entry-member TO <class>-members.
      ENDLOOP.
      APPEND classes TO dimensions.
    ENDLOOP.
    SORT ranked BY rank position.
    result-refused = VALUE #( FOR r IN ranked ( r-refusal ) ).

    " the holes of the product of the admitted members (none if a characteristic has no admitted member)
    DATA(complete) = xsdbool( dimensions IS NOT INITIAL ).
    LOOP AT dimensions INTO DATA(dimension) WHERE table_line IS INITIAL.
      complete = abap_false.
    ENDLOOP.
    IF complete = abap_true.
      collect_holes( EXPORTING dimensions = dimensions depth = 1 mask = 'FFFFFFFFFFFFFFFF' chosen = VALUE #( )
                     CHANGING  answer     = result ).
    ENDIF.

    " the first refusal names the status, a member before an aggregate (BW checks the aggregates with the
    " combinations, after the members); its combination is it with the first member of each other characteristic
    IF result-refused IS NOT INITIAL.
      DATA(refused) = result-refused[ 1 ].
      LOOP AT result-refused INTO DATA(candidate) WHERE member-kind <> zzxxmla1_if_bw_auth_check=>c_kind-aggregate.
        refused = candidate.
        EXIT.
      ENDLOOP.
      result-status = refused-status.
      result-reason = refused-reason.
      result-message = refused-message.
      LOOP AT groups INTO group.
        IF group-characteristic = refused-member-characteristic.
          APPEND refused-member TO result-combination.
        ELSE.
          APPEND group-entries[ 1 ]-member TO result-combination.
        ENDIF.
      ENDLOOP.
    ELSEIF result-holes IS NOT INITIAL.
      DATA(check) = zzxxmla1_cl_bw_auth=>refusal( reason = zzxxmla1_cl_bw_auth=>c_reason-combination
                                                  member = VALUE #( ) ).
      result-status = check-status.
      result-reason = check-reason.
      result-message = check-message.
      DATA(hole) = result-holes[ 1 ].
      LOOP AT hole INTO DATA(member).
        IF NOT line_exists( result-combination[ characteristic = member-characteristic ] ).
          APPEND member TO result-combination.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD collect_holes.
    DATA common TYPE ty_mask.
    DATA(classes) = dimensions[ depth ].
    LOOP AT classes INTO DATA(class).
      IF answer-more_holes = abap_true.
        RETURN.
      ENDIF.
      common = mask BIT-AND class-mask.
      DATA(members) = VALUE zzxxmla1_if_bw_auth_check=>ty_members( BASE chosen ( LINES OF class-members ) ).
      IF common IS INITIAL.
        " no authorization covers this combination: neither any below it
        LOOP AT dimensions INTO DATA(rest) FROM depth + 1.
          LOOP AT rest INTO DATA(other).
            APPEND LINES OF other-members TO members.
          ENDLOOP.
        ENDLOOP.
        IF lines( answer-holes ) >= zzxxmla1_if_bw_auth_check=>c_max_holes.
          answer-more_holes = abap_true.
          RETURN.
        ENDIF.
        APPEND members TO answer-holes.
      ELSEIF depth < lines( dimensions ).
        collect_holes( EXPORTING dimensions = dimensions depth = depth + 1 mask = common chosen = members
                       CHANGING  answer     = answer ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD error.
    result = VALUE #( status = zzxxmla1_if_bw_auth_check=>c_status-error reason = reason message = message ).
  ENDMETHOD.

  METHOD basic_of.
    " a reference characteristic has the hierarchies and the SID table of its basic one
    SELECT SINGLE chabasnm FROM rsdcha WHERE chanm = @iobjnm AND objvers = 'A' INTO @result.
    IF result IS INITIAL.
      result = iobjnm.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
