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
"! Whether a user may see a combination of members of an InfoProvider by BW's analysis authorizations, without MDX
"! (docs/next-steps.md, Now: analysis authorisations, The check for other callers). Made by
"! ZZXXMLA1_CL_BW_AUTH_CHECK=>for for one user, provider and key date.
"! <p>The check checks <strong>no authority of the caller</strong>: whom a caller may ask about is the caller's
"! responsibility.</p>
"! <p>A request is a cartesian product: its members grouped by characteristic, every combination of one member of
"! each characteristic is asked. It names every authorization-relevant characteristic of the provider
"! (characteristics), the aggregate as a member of kind A where totals are asked; a characteristic that is not
"! authorization relevant is not checked. The members are base members, by name, never an occurrence: a flat value,
"! a leaf (a value with its hierarchy), a node of a hierarchy (by name and InfoObject), or the aggregate.</p>
INTERFACE zzxxmla1_if_bw_auth_check
  PUBLIC.

  "! a member of a request:
  "! characteristic: the InfoObject (ZCLDOC);
  "! kind: V a value (a flat member, or a leaf where hierarchy is given), N a node of a hierarchy, A the aggregate;
  "! value: a value's key, NUMC with its zeros, # (or blank) the not-assigned one; a node's name; : (or blank) for
  "! the aggregate;
  "! hierarchy, version: the BW hierarchy a leaf or node is asked in (ZCLDOC_ORG, 001), blank for a flat value;
  "! node_iobjnm: a node's InfoObject (0HIER_NODE for a text node, an external characteristic such as ZCLSITE)
  TYPES: BEGIN OF ty_member,
           characteristic TYPE rsiobjnm,
           kind           TYPE c LENGTH 1,
           value          TYPE string,
           hierarchy      TYPE rshienm,
           version        TYPE rsversion,
           node_iobjnm    TYPE rsiobjnm,
         END OF ty_member.
  TYPES ty_members TYPE STANDARD TABLE OF ty_member WITH EMPTY KEY.
  "! a member no applying authorization admits, with BW's status, reason and message
  TYPES: BEGIN OF ty_refused,
           member  TYPE ty_member,
           status  TYPE c LENGTH 8,
           reason  TYPE c LENGTH 12,
           message TYPE string,
         END OF ty_refused.
  TYPES ty_refused_members TYPE STANDARD TABLE OF ty_refused WITH EMPTY KEY.
  "! a part of the request that is not authorized: the product of its members (grouped by characteristic)
  TYPES ty_products TYPE STANDARD TABLE OF ty_members WITH EMPTY KEY.
  TYPES ty_characteristics TYPE STANDARD TABLE OF rsiobjnm WITH EMPTY KEY.
  TYPES ty_auths TYPE STANDARD TABLE OF rsauth WITH EMPTY KEY.
  "! the answer:
  "! status: ALLOWED (every combination is authorized), NO AUTH, UNKNOWN (a value no authorization names) or ERROR
  "! (the request names something the provider does not have at the key date, or misses a characteristic);
  "! reason and message: BW's, of the first refused member (an aggregate only if no other member is refused), else of
  "! the first combination (or the error's);
  "! combination: a combination that is refused, one member per characteristic;
  "! refused: the members no authorization admits, in the order BW meets them walking the product (the last
  "! characteristic of the request fastest);
  "! holes: the parts of the product of the other members that no authorization covers, as sub-products; more_holes:
  "! there are more than c_max_holes
  TYPES: BEGIN OF ty_answer,
           status      TYPE c LENGTH 8,
           reason      TYPE c LENGTH 12,
           message     TYPE string,
           combination TYPE ty_members,
           refused     TYPE ty_refused_members,
           holes       TYPE ty_products,
           more_holes  TYPE abap_bool,
         END OF ty_answer.

  CONSTANTS: BEGIN OF c_kind,
               value     TYPE c LENGTH 1 VALUE 'V',
               node      TYPE c LENGTH 1 VALUE 'N',
               aggregate TYPE c LENGTH 1 VALUE 'A',
             END OF c_kind.
  CONSTANTS: BEGIN OF c_status,
               allowed TYPE c LENGTH 8 VALUE 'ALLOWED',
               no_auth TYPE c LENGTH 8 VALUE 'NO AUTH',
               unknown TYPE c LENGTH 8 VALUE 'UNKNOWN',
               error   TYPE c LENGTH 8 VALUE 'ERROR',
             END OF c_status.
  "! the reasons of an error; the reasons of a refusal are BW's (PROVIDER, VARIABLE, VALIDITY, NO VALUES, VALUE,
  "! HIERARCHY, NODE, COMBINATION)
  CONSTANTS: BEGIN OF c_error,
               missing   TYPE c LENGTH 12 VALUE 'MISSING',    " an authorization-relevant characteristic not asked
               request   TYPE c LENGTH 12 VALUE 'REQUEST',    " a member that is not well formed
               hierarchy TYPE c LENGTH 12 VALUE 'NO SLICE',   " a hierarchy without a slice at the key date
               member    TYPE c LENGTH 12 VALUE 'NO MEMBER',  " a node, leaf or value the provider does not have
             END OF c_error.
  CONSTANTS c_aggregate TYPE string VALUE `:`.
  CONSTANTS c_max_holes TYPE i VALUE 100.

  "! Whether every combination of the request's members is authorized; reads only, no commit.
  "! @raising zzxxmla1_cx_bw_auth_check | a characteristic the provider does not have
  METHODS check
    IMPORTING request       TYPE ty_members
    RETURNING VALUE(result) TYPE ty_answer
    RAISING   zzxxmla1_cx_bw_auth_check.
  "! The provider's authorization-relevant characteristics, which a request names.
  METHODS characteristics
    RETURNING VALUE(result) TYPE ty_characteristics.
  "! The user's authorizations that apply to the provider.
  METHODS applying
    RETURNING VALUE(result) TYPE ty_auths.
ENDINTERFACE.
