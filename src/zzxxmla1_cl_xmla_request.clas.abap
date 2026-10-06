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
CLASS zzxxmla1_cl_xmla_request DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_pair,
        name  TYPE string,
        value TYPE string,
      END OF ty_pair,
      ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY.
    " What the client asked: Discover (a RequestType, Restrictions and Properties) or Execute (a statement and
    " Properties), and the session header element: BEGIN (BeginSession), WITHIN (Session) or END (EndSession) with
    " the SessionId of the client, or empty.
    TYPES:
      BEGIN OF ty_request,
        method        TYPE string,
        type          TYPE string,
        restrictions  TYPE ty_t_pair,
        properties    TYPE ty_t_pair,
        statement     TYPE string,
        session_state TYPE string,
        session_id    TYPE string,
      END OF ty_request.

    "! Parses the SOAP envelope and checks it the way the reference does (xmla.impl.DefaultXmlaServlet and
    "! DefaultXmlaRequest), in the same order and with the same faults: not XML or not a SOAP envelope, more than one
    "! Header or not one Body, a mustUnderstand header element nobody knows, not exactly one Discover or Execute, then
    "! the number of RequestType, Properties, Restrictions, PropertyList, RestrictionList and Command elements.
    CLASS-METHODS parse
      IMPORTING xml           TYPE string
      RETURNING VALUE(result) TYPE ty_request
      RAISING   zzxxmla1_cx_xmla.

  PRIVATE SECTION.
    TYPES ty_t_element TYPE STANDARD TABLE OF REF TO if_ixml_element WITH EMPTY KEY.
    CONSTANTS c_ns_soap   TYPE string VALUE `http://schemas.xmlsoap.org/soap/envelope/`.
    CONSTANTS c_ns_xmla   TYPE string VALUE `urn:schemas-microsoft-com:xml-analysis`.
    CONSTANTS c_ns_secext TYPE string VALUE `http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd`.

    "! The child elements with that name in that namespace; an empty namespace or name matches any.
    CLASS-METHODS elements
      IMPORTING parent        TYPE REF TO if_ixml_element
                namespace     TYPE string OPTIONAL
                name          TYPE string OPTIONAL
      RETURNING VALUE(result) TYPE ty_t_element.
    "! A fault of the client: kind Client, the code and its fixed text of XmlaConstants.
    CLASS-METHODS fail
      IMPORTING kind        TYPE string DEFAULT `Client`
                code        TYPE string
                text        TYPE string
                description TYPE string
                error_code  TYPE string DEFAULT `3238658121`
      RAISING   zzxxmla1_cx_xmla.
    "! Wrong number of XMLA elements: the reference's message "Invalid XML/A message: Wrong number of X elements: n".
    CLASS-METHODS wrong_number
      IMPORTING code    TYPE string
                text    TYPE string
                element TYPE string
                count   TYPE i
      RAISING   zzxxmla1_cx_xmla.
    "! DefaultXmlaServlet.handleSoapHeader: faults for header elements nobody knows, and the session element.
    CLASS-METHODS check_header
      IMPORTING header  TYPE REF TO if_ixml_element
      CHANGING  request TYPE ty_request
      RAISING   zzxxmla1_cx_xmla.
    CLASS-METHODS read_properties
      IMPORTING properties    TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_t_pair
      RAISING   zzxxmla1_cx_xmla.
    CLASS-METHODS read_restrictions
      IMPORTING restrictions  TYPE REF TO if_ixml_element
      RETURNING VALUE(result) TYPE ty_t_pair
      RAISING   zzxxmla1_cx_xmla.
ENDCLASS.

CLASS zzxxmla1_cl_xmla_request IMPLEMENTATION.

  METHOD parse.
    DATA(ixml) = cl_ixml=>create( ).
    DATA(document) = ixml->create_document( ).
    DATA(factory) = ixml->create_stream_factory( ).
    DATA(stream) = factory->create_istream_string( xml ).
    DATA(parser) = ixml->create_parser( stream_factory = factory istream = stream document = document ).
    IF parser->parse( ) <> 0.
      DATA(reason) = VALUE string( ).
      IF parser->num_errors( ) > 0.
        reason = parser->get_error( index = 0 )->get_reason( ).
      ENDIF.
      fail( code = `00USMC02` text = `DOM parse errors occur` description = reason ).
    ENDIF.

    DATA(envelope) = document->get_root_element( ).
    IF envelope IS NOT BOUND OR envelope->get_name( ) <> `Envelope`.
      fail( code = `00USMC02` text = `DOM parse errors occur` description = `Invalid SOAP message: Top element not Envelope` ).
    ENDIF.
    IF envelope->get_namespace_uri( ) <> c_ns_soap.
      fail( code = `00USMC02` text = `DOM parse errors occur`
            description = `Invalid SOAP message: Envelope element not in SOAP namespace` ).
    ENDIF.
    DATA(headers) = elements( parent = envelope namespace = c_ns_soap name = `Header` ).
    IF lines( headers ) > 1.
      fail( code = `00USMC02` text = `DOM parse errors occur` description = `Invalid SOAP message: More than one Header elements` ).
    ENDIF.
    DATA(bodies) = elements( parent = envelope namespace = c_ns_soap name = `Body` ).
    IF lines( bodies ) <> 1.
      fail( code = `00USMC02` text = `DOM parse errors occur` description = `Invalid SOAP message: Does not have one Body element` ).
    ENDIF.

    IF headers IS NOT INITIAL.
      check_header( EXPORTING header = headers[ 1 ] CHANGING request = result ).
    ENDIF.

    DATA(discovers) = elements( parent = bodies[ 1 ] namespace = c_ns_xmla name = `Discover` ).
    DATA(executes) = elements( parent = bodies[ 1 ] namespace = c_ns_xmla name = `Execute` ).
    IF lines( discovers ) + lines( executes ) <> 1.
      fail( code = `00HSBA01` text = `SOAP Body not correctly formed`
            description = |Invalid XML/A message: Body has { lines( discovers ) } Discover Requests and { lines( executes ) } Execute Requests| ).
    ENDIF.

    IF discovers IS NOT INITIAL.
      DATA(discover) = discovers[ 1 ].
      result-method = `DISCOVER`.
      DATA(request_types) = elements( parent = discover namespace = c_ns_xmla name = `RequestType` ).
      IF lines( request_types ) <> 1.
        wrong_number( code = `00HSBB04` text = `XMLA SOAP bad Discover RequestType element` element = `RequestType` count = lines( request_types ) ).
      ENDIF.
      result-type = request_types[ 1 ]->get_value( ).
      DATA(properties) = elements( parent = discover namespace = c_ns_xmla name = `Properties` ).
      IF lines( properties ) <> 1.
        wrong_number( code = `00HSBB06` text = `XMLA SOAP bad Discover or Execute Properties element` element = `Properties` count = lines( properties ) ).
      ENDIF.
      result-properties = read_properties( properties[ 1 ] ).
      DATA(restrictions) = elements( parent = discover namespace = c_ns_xmla name = `Restrictions` ).
      IF lines( restrictions ) <> 1.
        wrong_number( code = `00HSBB05` text = `XMLA SOAP bad Discover Restrictions element` element = `Restrictions` count = lines( restrictions ) ).
      ENDIF.
      result-restrictions = read_restrictions( restrictions[ 1 ] ).
    ELSE.
      DATA(execute) = executes[ 1 ].
      result-method = `EXECUTE`.
      DATA(commands) = elements( parent = execute namespace = c_ns_xmla name = `Command` ).
      IF lines( commands ) <> 1.
        wrong_number( code = `00HSBB07` text = `XMLA SOAP bad Execute Command element` element = `Command` count = lines( commands ) ).
      ENDIF.
      DATA(command_children) = elements( parent = commands[ 1 ] ).
      IF lines( command_children ) <> 1.
        wrong_number( code = `00HSBB07` text = `XMLA SOAP bad Execute Command element` element = `Command children` count = lines( command_children ) ).
      ENDIF.
      IF to_upper( command_children[ 1 ]->get_name( ) ) = `STATEMENT`.
        result-statement = replace( val = command_children[ 1 ]->get_value( ) sub = cl_abap_char_utilities=>cr_lf with = cl_abap_char_utilities=>newline occ = 0 ).
      ENDIF.
      properties = elements( parent = execute namespace = c_ns_xmla name = `Properties` ).
      IF lines( properties ) <> 1.
        wrong_number( code = `00HSBB06` text = `XMLA SOAP bad Discover or Execute Properties element` element = `Properties` count = lines( properties ) ).
      ENDIF.
      result-properties = read_properties( properties[ 1 ] ).
    ENDIF.
  ENDMETHOD.

  METHOD elements.
    DATA(iterator) = parent->get_children( )->create_iterator( ).
    DATA(node) = iterator->get_next( ).
    WHILE node IS BOUND.
      IF node->get_type( ) = if_ixml_node=>co_node_element.
        DATA(element) = CAST if_ixml_element( node ).
        IF ( name IS INITIAL OR element->get_name( ) = name ) AND ( namespace IS INITIAL OR element->get_namespace_uri( ) = namespace ).
          APPEND element TO result.
        ENDIF.
      ENDIF.
      node = iterator->get_next( ).
    ENDWHILE.
  ENDMETHOD.

  METHOD fail.
    zzxxmla1_cx_xmla=>raise_code( kind = kind code = code text = text description = description error_code = error_code ).
  ENDMETHOD.

  METHOD wrong_number.
    " Util.newError of the reference puts "olap4abap Error:Internal error: " in front of the message
    fail( code = code text = text
          description = |olap4abap Error:Internal error: Invalid XML/A message: Wrong number of { element } elements: { count }| ).
  ENDMETHOD.

  METHOD check_header.
    " Header elements the server does not know and that must be understood (XMLA namespace, mustUnderstand not 0) are
    " faults. Sessions keep no state on this server (it only reads): the id of a Session or EndSession element is
    " taken as it is, where the reference faults for one it does not know; the handler gives a new one for BeginSession.
    LOOP AT elements( header ) INTO DATA(child).
      DATA(name) = child->get_name( ).
      IF name = `Security` AND child->get_namespace_uri( ) = c_ns_secext.
        CONTINUE.
      ENDIF.
      DATA(must_understand) = child->get_attribute_node( `mustUnderstand` ).
      IF must_understand IS BOUND AND must_understand->get_value( ) <> `1`.
        CONTINUE.
      ENDIF.
      IF child->get_namespace_uri( ) <> c_ns_xmla.
        CONTINUE.
      ENDIF.
      CASE name.
        WHEN `BeginSession`.
          request-session_state = `BEGIN`.
          CLEAR request-session_id.
        WHEN `Session` OR `EndSession`.
          request-session_state = COND #( WHEN name = `Session` THEN `WITHIN` ELSE `END` ).
          DATA(session_id) = child->get_attribute_node( `SessionId` ).
          IF session_id IS NOT BOUND.
            fail( kind = `Server` code = `00HSHU01` text = `Unknown error handle soap header`
                  description = |Invalid XML/A message: { name } Header element with no SessionId attribute|
                  error_code = `3238789130` ).
          ENDIF.
          request-session_id = session_id->get_value( ).
        WHEN OTHERS.
          fail( kind = `MustUnderstand` code = `00HSHA01` text = `SOAP Header must understand element not recognized`
                description = |Invalid XML/A message: Unknown "mustUnderstand" XMLA Header element "{ name }"| ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_properties.
    DATA(lists) = elements( parent = properties namespace = c_ns_xmla name = `PropertyList` ).
    IF lines( lists ) > 1.
      wrong_number( code = `00HSBB09` text = `XMLA SOAP bad Discover or Execute PropertyList element`
                    element = `PropertyList` count = lines( lists ) ).
    ENDIF.
    IF lists IS NOT INITIAL.
      LOOP AT elements( parent = lists[ 1 ] namespace = c_ns_xmla ) INTO DATA(property).
        APPEND VALUE #( name = property->get_name( ) value = property->get_value( ) ) TO result.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD read_restrictions.
    DATA(lists) = elements( parent = restrictions namespace = c_ns_xmla name = `RestrictionList` ).
    IF lines( lists ) > 1.
      wrong_number( code = `00HSBB08` text = `XMLA SOAP too many Discover RestrictionList element`
                    element = `RestrictionList` count = lines( lists ) ).
    ENDIF.
    IF lists IS NOT INITIAL.
      LOOP AT elements( parent = lists[ 1 ] namespace = c_ns_xmla ) INTO DATA(restriction).
        " the value is the text of the element, or the text of each child element if there are some
        DATA(values) = elements( restriction ).
        IF values IS INITIAL.
          APPEND VALUE #( name = restriction->get_name( ) value = restriction->get_value( ) ) TO result.
        ELSE.
          LOOP AT values INTO DATA(value).
            APPEND VALUE #( name = restriction->get_name( ) value = value->get_value( ) ) TO result.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

ENDCLASS.