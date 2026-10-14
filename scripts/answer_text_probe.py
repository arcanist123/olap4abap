#!/usr/bin/env python3
"""Benchmarks ways to write the cells of an Execute answer (docs/query-planning.md, Cells first (step 4)): the
1,001 x 1,001 grid on ZXMLWIDEA has 633,830 cells with a value, asked with Excel's cell properties (VALUE,
FORMAT_STRING, LANGUAGE, BACK_COLOR, FORE_COLOR, FONT_FLAGS), so each cell is

        <Cell CellOrdinal="123">
          <Value xsi:type="xsd:double">4567</Value>
          <FormatString>Standard</FormatString>
          <FontFlags>0</FontFlags>
        </Cell>

Every variant turns the same cells (ordinal and value text, made up in the program) into the UTF-8 bytes of the
CellData element, the form the HTTP response sends:

    pieces    today's ZZXXMLA1_CL_XMLA_MDDATASET=>cell_xml: the elements appended piece by piece, a line per cell in
              a table, joined once (concat_lines_of), converted to UTF-8 (what set_cdata does)
    template  one string template per cell into a table, joined once, converted to UTF-8
    chunks    one string template per cell, joined and converted per 10,000 cells, the parts concatenated as
              xstrings (appending the response in parts, append_cdata, converts each part)
    xchunks   as chunks, but the parts kept in a table of xstrings (the response appends each, nothing joined)
    sxml      the sXML writer (CL_SXML_STRING_WRITER, UTF-8 into an xstring), token calls, no indentation
    kernel    CALL TRANSFORMATION id of the cell table (asXML, not the answer's shape): how fast the kernel
              serializes such a table, a bound for a simple transformation

Times are milliseconds (GET RUN TIME), best of the repetitions; size is the bytes written. One sapcli abap run.

    python scripts/answer_text_probe.py
    python scripts/answer_text_probe.py --cells 100000 --reps 3
"""
import argparse
import importlib.util
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("sap_files", ROOT / "scripts" / "sap-files.py")
sap_files = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sap_files)

VARIANTS = ["pieces", "template", "chunks", "xchunks", "sxml", "kernel"]


def program(cells, reps, variants):
    lines = [
        "TYPES: BEGIN OF ty_cell, ordinal TYPE i, value TYPE string, END OF ty_cell.",
        "DATA cells TYPE STANDARD TABLE OF ty_cell WITH EMPTY KEY.",
        "DATA t0 TYPE i.",
        "DATA t1 TYPE i.",
        "DATA bytes TYPE xstring.",
        "DATA size TYPE i.",
        "DATA parts_size TYPE i.",
        "DATA ms TYPE i.",
        "DATA nl TYPE string.",
        "nl = cl_abap_char_utilities=>newline.",
        # ordinals spread over the grid as the facts fill it (63 %), values with up to 6 digits
        f"DATA(random) = cl_abap_random_int=>create( seed = 42 min = 1 max = 999999 ).",
        "DATA(ordinal) = 0.",
        f"WHILE lines( cells ) < {cells}.",
        "  IF random->get_next( ) MOD 100 < 63.",
        "    APPEND VALUE #( ordinal = ordinal value = |{ random->get_next( ) }| ) TO cells.",
        "  ENDIF.",
        "  ordinal = ordinal + 1.",
        "ENDWHILE.",
        "DATA best TYPE i.",
        "DATA times TYPE string.",
    ]

    def timed(name, body):
        return [
            f"best = 0.",
            f"times = ``.",
            f"DO {reps} TIMES.",
            "  CLEAR bytes.",
            "  GET RUN TIME FIELD t0.",
            *["  " + b for b in body],
            "  GET RUN TIME FIELD t1.",
            "  size = xstrlen( bytes ) + parts_size.",
            "  CLEAR parts_size.",
            "  CLEAR bytes.",
            "  ms = ( t1 - t0 ) / 1000.",
            "  times = times && | { ms }|.",
            "  IF best = 0 OR ms < best.",
            "    best = ms.",
            "  ENDIF.",
            "ENDDO.",
            f"out->write( |{name:<9} best {{ best WIDTH = 6 }} ms  size {{ size WIDTH = 10 }} bytes  (ms:{{ times }})| ).",
        ]

    bodies = {
        "pieces": [
            "DATA(pieces_lines) = VALUE string_table( ).",
            "LOOP AT cells ASSIGNING FIELD-SYMBOL(<p>).",
            "  DATA(elements) = ``.",
            "  elements = elements && |          <Value xsi:type=\"{ `xsd:double` }\">| && <p>-value && `</Value>` && nl.",
            "  elements = elements && |          <FormatString>{ escape( val = `Standard` format = cl_abap_format=>e_xml_text ) }</FormatString>| && nl.",
            "  elements = elements && `          <FontFlags>0</FontFlags>` && nl.",
            "  APPEND |        <Cell CellOrdinal=\"{ <p>-ordinal }\">| && nl && elements && `        </Cell>` && nl TO pieces_lines.",
            "ENDLOOP.",
            "bytes = cl_abap_codepage=>convert_to( concat_lines_of( pieces_lines ) ).",
            "CLEAR pieces_lines.",
        ],
        "template": [
            "DATA(template_lines) = VALUE string_table( ).",
            "LOOP AT cells ASSIGNING FIELD-SYMBOL(<t>).",
            "  APPEND |        <Cell CellOrdinal=\"{ <t>-ordinal }\">\\n          <Value xsi:type=\"xsd:double\">{ <t>-value }</Value>\\n|",
            "      && |          <FormatString>Standard</FormatString>\\n          <FontFlags>0</FontFlags>\\n        </Cell>\\n|",
            "      TO template_lines.",
            "ENDLOOP.",
            "bytes = cl_abap_codepage=>convert_to( concat_lines_of( template_lines ) ).",
            "CLEAR template_lines.",
        ],
        "chunks": [
            "DATA(chunk_lines) = VALUE string_table( ).",
            "LOOP AT cells ASSIGNING FIELD-SYMBOL(<c>).",
            "  APPEND |        <Cell CellOrdinal=\"{ <c>-ordinal }\">\\n          <Value xsi:type=\"xsd:double\">{ <c>-value }</Value>\\n|",
            "      && |          <FormatString>Standard</FormatString>\\n          <FontFlags>0</FontFlags>\\n        </Cell>\\n|",
            "      TO chunk_lines.",
            "  IF lines( chunk_lines ) = 10000.",
            "    DATA(part) = cl_abap_codepage=>convert_to( concat_lines_of( chunk_lines ) ).",
            "    CONCATENATE bytes part INTO bytes IN BYTE MODE.",
            "    CLEAR chunk_lines.",
            "  ENDIF.",
            "ENDLOOP.",
            "part = cl_abap_codepage=>convert_to( concat_lines_of( chunk_lines ) ).",
            "CONCATENATE bytes part INTO bytes IN BYTE MODE.",
            "CLEAR chunk_lines.",
        ],
        "xchunks": [
            "DATA(xchunk_lines) = VALUE string_table( ).",
            "DATA xparts TYPE STANDARD TABLE OF xstring WITH EMPTY KEY.",
            "CLEAR xparts.",
            "LOOP AT cells ASSIGNING FIELD-SYMBOL(<x>).",
            "  APPEND |        <Cell CellOrdinal=\"{ <x>-ordinal }\">\\n          <Value xsi:type=\"xsd:double\">{ <x>-value }</Value>\\n|",
            "      && |          <FormatString>Standard</FormatString>\\n          <FontFlags>0</FontFlags>\\n        </Cell>\\n|",
            "      TO xchunk_lines.",
            "  IF lines( xchunk_lines ) = 10000.",
            "    APPEND cl_abap_codepage=>convert_to( concat_lines_of( xchunk_lines ) ) TO xparts.",
            "    CLEAR xchunk_lines.",
            "  ENDIF.",
            "ENDLOOP.",
            "APPEND cl_abap_codepage=>convert_to( concat_lines_of( xchunk_lines ) ) TO xparts.",
            "CLEAR xchunk_lines.",
            # the size only: the response would take the parts one by one
            "LOOP AT xparts INTO DATA(xpart).",
            "  parts_size = parts_size + xstrlen( xpart ).",
            "ENDLOOP.",
            "CLEAR xparts.",
        ],
        "sxml": [
            "DATA(writer) = CAST if_sxml_writer( cl_sxml_string_writer=>create( type = if_sxml=>co_xt_xml10 ) ).",
            "writer->open_element( name = `CellData` ).",
            "writer->write_namespace_declaration( nsuri = `http://www.w3.org/2001/XMLSchema-instance` prefix = `xsi` ).",
            "LOOP AT cells ASSIGNING FIELD-SYMBOL(<s>).",
            "  writer->open_element( name = `Cell` ).",
            "  writer->write_attribute( name = `CellOrdinal` value = |{ <s>-ordinal }| ).",
            "  writer->open_element( name = `Value` ).",
            "  writer->write_attribute( name = `type` nsuri = `http://www.w3.org/2001/XMLSchema-instance` prefix = `xsi` value = `xsd:double` ).",
            "  writer->write_value( <s>-value ).",
            "  writer->close_element( ).",
            "  writer->open_element( name = `FormatString` ).",
            "  writer->write_value( `Standard` ).",
            "  writer->close_element( ).",
            "  writer->open_element( name = `FontFlags` ).",
            "  writer->write_value( `0` ).",
            "  writer->close_element( ).",
            "  writer->close_element( ).",
            "ENDLOOP.",
            "writer->close_element( ).",
            "bytes = CAST cl_sxml_string_writer( writer )->get_output( ).",
            "CLEAR writer.",
        ],
        "kernel": [
            "CALL TRANSFORMATION id SOURCE cells = cells RESULT XML bytes.",
        ],

    }
    for name in variants:
        lines += timed(name, bodies[name])
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cells", type=int, default=633830)
    parser.add_argument("--reps", type=int, default=2)
    parser.add_argument("--variant", nargs="*", choices=VARIANTS, default=VARIANTS)
    parser.add_argument("--print", action="store_true", help="print the program and run nothing")
    args = parser.parse_args()
    code = program(args.cells, args.reps, args.variant)
    if args.print:
        print(code)
        return
    print(f"{args.cells} cells, best of {args.reps}", flush=True)
    print(sap_files.run_abap(code).rstrip(), flush=True)


if __name__ == "__main__":
    main()
