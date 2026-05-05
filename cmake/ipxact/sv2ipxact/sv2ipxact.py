#!/usr/bin/env python3
"""
sv2ipxact.py — SystemVerilog (IEEE 1800-2022) module header to IP-XACT (IEEE 1685-2022) converter.

Parses:
  - Module parameters / localparams
  - Ports (input / output / inout) with packed & unpacked dimensions
  - Interface ports with optional modport
  - Typedefs / struct / enum / union used in the port list

Usage:
  python3 sv2ipxact.py --input <file.sv> --output <file.xml> \\
                       --vendor <vendor> --library <library> \\
                       [--version <version>]
"""

import re
import sys
import argparse
import textwrap
from pathlib import Path
from xml.etree import ElementTree as ET
from xml.dom import minidom
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class SVParam:
    name: str
    param_type: str          # "parameter" | "localparam"
    data_type: str           # e.g. "integer", "logic [7:0]", "string"
    default_value: str       # raw string or ""
    description: str = ""


@dataclass
class SVPort:
    name: str
    direction: str           # "input" | "output" | "inout"
    data_type: str           # e.g. "logic", "wire", "reg", typedef name …
    packed_dims: str         # e.g. "[7:0]" or ""
    unpacked_dims: str       # e.g. "[0:3]" or ""
    description: str = ""


@dataclass
class SVInterfacePort:
    name: str
    interface_type: str      # interface name
    modport: str             # modport name or ""
    description: str = ""


@dataclass
class SVTypedef:
    name: str
    definition: str          # raw text after "typedef"


@dataclass
class SVModule:
    name: str
    parameters: list = field(default_factory=list)
    ports: list = field(default_factory=list)
    interface_ports: list = field(default_factory=list)
    typedefs: list = field(default_factory=list)


# ---------------------------------------------------------------------------
# Pre-processing helpers
# ---------------------------------------------------------------------------

def strip_comments(text: str) -> str:
    """Remove // line comments and /* … */ block comments, preserving line count."""
    # Block comments
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group().count('\n'), text, flags=re.DOTALL)
    # Line comments
    text = re.sub(r'//[^\n]*', '', text)
    return text


def extract_module_header(text: str) -> Optional[str]:
    """
    Return the text from 'module <name>' up to (but not including) the
    first ';' that closes the port/parameter list, i.e. the module declaration.
    """
    m = re.search(r'\bmodule\b', text)
    if not m:
        return None
    # Find matching closing ')' then the ';'
    start = m.start()
    # Walk forward to find the ';' that ends the declaration
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ';' and depth == 0:
            return text[start:i + 1]
        i += 1
    return text[start:]   # unterminated — return what we have


def collect_typedefs(text: str) -> list[SVTypedef]:
    """Scan the whole file for typedef declarations (used in port list)."""
    typedefs = []
    pattern = re.compile(
        r'\btypedef\b\s+'
        r'((?:struct|union|enum)\s*(?:packed\s*)?(?:\{[^}]*\}|[^;{]*)|[^;]+?)\s+'
        r'(\w+)\s*;',
        re.DOTALL
    )
    for m in pattern.finditer(text):
        typedefs.append(SVTypedef(name=m.group(2).strip(), definition=m.group(1).strip()))
    return typedefs


# ---------------------------------------------------------------------------
# Tokeniser / normaliser
# ---------------------------------------------------------------------------

def normalise_ws(s: str) -> str:
    return re.sub(r'\s+', ' ', s).strip()


def split_top_level(text: str, sep: str = ',') -> list[str]:
    """Split `text` on `sep` only at parenthesis/bracket depth 0."""
    parts = []
    depth = 0
    current = []
    for ch in text:
        if ch in '([':
            depth += 1
        elif ch in ')]':
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(''.join(current).strip())
            current = []
        else:
            current.append(ch)
    if current:
        parts.append(''.join(current).strip())
    return [p for p in parts if p]


# ---------------------------------------------------------------------------
# Parameter parser
# ---------------------------------------------------------------------------

_PARAM_KW = re.compile(r'^(parameter|localparam)\b', re.IGNORECASE)
_PARAM_ENTRY = re.compile(
    r'^(?P<kw>parameter|localparam)\s*'
    r'(?P<dtype>[^=\w]*(?:(?:logic|bit|int(?:eger)?|byte|shortint|longint|'
    r'real|shortreal|string|time)\b[^=]*?)?)?'
    r'\b(?P<name>\w+)\s*'
    r'(?:=\s*(?P<val>.+))?$',
    re.IGNORECASE | re.DOTALL
)

def parse_parameter_block(block: str) -> list[SVParam]:
    """Parse the content of #( … ) parameter list."""
    # Remove outer parens if present
    block = block.strip()
    if block.startswith('(') and block.endswith(')'):
        block = block[1:-1]

    params = []
    entries = split_top_level(block)
    current_kw = 'parameter'
    current_dtype = ''

    for entry in entries:
        entry = normalise_ws(entry)
        if not entry:
            continue
        m = _PARAM_ENTRY.match(entry)
        if m:
            kw = m.group('kw') or current_kw
            current_kw = kw
            dtype = normalise_ws(m.group('dtype') or current_dtype or 'int')
            current_dtype = dtype
            name = m.group('name')
            val = normalise_ws(m.group('val') or '')
            params.append(SVParam(
                name=name,
                param_type=kw.lower(),
                data_type=dtype,
                default_value=val,
            ))
        else:
            # Could be a bare "name = val" with inherited type
            m2 = re.match(r'^(\w+)\s*(?:=\s*(.+))?$', entry)
            if m2:
                params.append(SVParam(
                    name=m2.group(1),
                    param_type=current_kw,
                    data_type=current_dtype or 'int',
                    default_value=normalise_ws(m2.group(2) or ''),
                ))
    return params


# ---------------------------------------------------------------------------
# Port parser
# ---------------------------------------------------------------------------

_DIR = re.compile(r'^(input|output|inout)\b', re.IGNORECASE)
_PACKED_DIM = re.compile(r'(\[(?:[^\[\]]*|\[[^\[\]]*\])*\])')
_INTF_PORT = re.compile(
    r'^(?P<iface>\w+)(?:\.(?P<modport>\w+))?\s+(?P<name>\w+)(?P<udims>(?:\s*\[[^\]]*\])*)$'
)

# Scalar / vector built-in types
_BUILTIN_TYPES = re.compile(
    r'^(?:logic|wire|reg|bit|int(?:eger)?|byte|shortint|longint|'
    r'real|shortreal|time|tri|supply[01]|uwire)\b',
    re.IGNORECASE
)

def classify_port(entry: str, known_types: set[str]) -> SVPort | SVInterfacePort | None:
    """
    Parse one port entry and return an SVPort, SVInterfacePort, or None.
    `known_types` is the set of typedef names visible in the file.
    """
    entry = normalise_ws(entry)
    if not entry:
        return None

    # --- Directional port ---
    dm = _DIR.match(entry)
    if dm:
        direction = dm.group(1).lower()
        rest = entry[dm.end():].strip()

        # ── Strategy: tokenise rest into words/brackets, then decide boundary
        # Grammar of what follows the direction keyword:
        #   [type_keywords]* [packed_dims]* identifier [unpacked_dims]*
        #
        # Type keywords (built-ins only; user-defined types are a single \w+)
        _BUILTIN_KW = re.compile(
            r'^(logic|wire|reg|bit|int(?:eger)?|byte|shortint|longint|'
            r'real|shortreal|time|signed|unsigned|tri|supply[01]|uwire)\b',
            re.IGNORECASE
        )
        _DIM  = re.compile(r'^\[[^\]]*\]')    # one [...] token

        tokens = []  # list of ('kw'|'dim'|'id', value)
        s = rest
        while s:
            s = s.strip()
            if not s:
                break
            m_kw = _BUILTIN_KW.match(s)
            if m_kw:
                tokens.append(('kw', m_kw.group(0)))
                s = s[m_kw.end():]
                continue
            m_dim = _DIM.match(s)
            if m_dim:
                tokens.append(('dim', m_dim.group(0)))
                s = s[m_dim.end():]
                continue
            m_id = re.match(r'^(\w+)', s)
            if m_id:
                tokens.append(('id', m_id.group(1)))
                s = s[m_id.end():]
                continue
            break   # unexpected char

        # The last 'id' token is the port name; everything before is type+dims.
        # Any 'dim' after the name token are unpacked dims.
        # Identify the name token index (last 'id')
        name_idx = None
        for i in range(len(tokens) - 1, -1, -1):
            if tokens[i][0] == 'id':
                name_idx = i
                break

        if name_idx is None:
            return None   # malformed

        name = tokens[name_idx][1]

        # Build dtype from keyword tokens before name (skip dims between kws for now)
        dtype_parts = [v for (k, v) in tokens[:name_idx] if k == 'kw']
        dtype = ' '.join(dtype_parts) if dtype_parts else 'logic'

        # A single user-defined type (no kw before the name, name_idx > 0, prior token is id)
        if not dtype_parts and name_idx > 0 and tokens[name_idx - 1][0] == 'id':
            dtype = tokens[name_idx - 1][1]

        # Packed dims: dim tokens before the name
        packed_dims = ' '.join(v for (k, v) in tokens[:name_idx] if k == 'dim')

        # Unpacked dims: dim tokens after the name
        unpacked_dims = ' '.join(v for (k, v) in tokens[name_idx + 1:] if k == 'dim')

        return SVPort(name=name, direction=direction, data_type=dtype,
                      packed_dims=packed_dims, unpacked_dims=unpacked_dims)

    # --- Interface port (no direction keyword) ---
    im = _INTF_PORT.match(entry)
    if im:
        first_word = im.group('iface')
        # Only treat as interface port if it looks like a user type
        if not _BUILTIN_TYPES.match(first_word):
            return SVInterfacePort(
                name=im.group('name'),
                interface_type=first_word,
                modport=im.group('modport') or '',
            )

    return None


def parse_port_list(block: str, known_types: set[str]) -> tuple[list[SVPort], list[SVInterfacePort]]:
    """Parse the content of the port list ( … )."""
    block = block.strip()
    if block.startswith('(') and block.endswith(')'):
        block = block[1:-1]

    ports: list[SVPort] = []
    iface_ports: list[SVInterfacePort] = []
    entries = split_top_level(block)

    current_dir = None
    current_dtype = 'logic'
    current_packed = ''

    for entry in entries:
        entry = normalise_ws(entry)
        if not entry:
            continue

        result = classify_port(entry, known_types)
        if isinstance(result, SVPort):
            current_dir = result.direction
            current_dtype = result.data_type
            current_packed = result.packed_dims
            ports.append(result)
        elif isinstance(result, SVInterfacePort):
            iface_ports.append(result)
        else:
            # Implicit continuation: same direction/type as previous port
            # e.g.  "input logic a, b, c"  → b and c inherit
            if current_dir:
                name_match = re.match(r'^(\w+)((?:\s*\[[^\]]*\])*)\s*$', entry)
                if name_match:
                    ports.append(SVPort(
                        name=name_match.group(1),
                        direction=current_dir,
                        data_type=current_dtype,
                        packed_dims=current_packed,
                        unpacked_dims=normalise_ws(name_match.group(2)),
                    ))
    return ports, iface_ports


# ---------------------------------------------------------------------------
# Top-level SV parser
# ---------------------------------------------------------------------------

def parse_sv_module(source: str) -> Optional[SVModule]:
    clean = strip_comments(source)
    typedefs = collect_typedefs(clean)
    known_types = {t.name for t in typedefs}

    header = extract_module_header(clean)
    if not header:
        return None

    # Module name
    name_m = re.search(r'\bmodule\s+(\w+)', header)
    if not name_m:
        return None
    module_name = name_m.group(1)

    mod = SVModule(name=module_name, typedefs=typedefs)

    # Parameter list  #( … )
    param_m = re.search(r'#\s*(\()', header)
    if param_m:
        # find matching closing paren
        start = param_m.start(1)
        depth = 0
        end = start
        for i in range(start, len(header)):
            if header[i] == '(':
                depth += 1
            elif header[i] == ')':
                depth -= 1
                if depth == 0:
                    end = i
                    break
        param_block = header[start:end + 1]
        mod.parameters = parse_parameter_block(param_block)

    # Port list  ( … ) — the last top-level parens group
    # Find it: after the module name (and optional param list)
    search_start = name_m.end()
    if param_m:
        search_start = end + 1   # after param block

    port_m = re.search(r'\(', header[search_start:])
    if port_m:
        abs_start = search_start + port_m.start()
        depth = 0
        abs_end = abs_start
        for i in range(abs_start, len(header)):
            if header[i] == '(':
                depth += 1
            elif header[i] == ')':
                depth -= 1
                if depth == 0:
                    abs_end = i
                    break
        port_block = header[abs_start:abs_end + 1]
        mod.ports, mod.interface_ports = parse_port_list(port_block, known_types)

    return mod


# ---------------------------------------------------------------------------
# IP-XACT 2022 XML generation
# ---------------------------------------------------------------------------

IPXACT_NS  = 'http://www.accellera.org/XMLSchema/IPXACT/1685-2022'
XSI_NS     = 'http://www.w3.org/2001/XMLSchema-instance'
SCHEMA_LOC = ('http://www.accellera.org/XMLSchema/IPXACT/1685-2022 '
              'http://www.accellera.org/XMLSchema/IPXACT/1685-2022/index.xsd')

def _tag(local: str) -> str:
    return f'{{{IPXACT_NS}}}{local}'


def _sub(parent: ET.Element, local: str, text: str = None) -> ET.Element:
    el = ET.SubElement(parent, _tag(local))
    if text is not None:
        el.text = text
    return el


def direction_to_ipxact(sv_dir: str) -> str:
    return {'input': 'in', 'output': 'out', 'inout': 'inout'}.get(sv_dir, 'in')


def packed_dim_to_vectors(packed: str) -> tuple[Optional[str], Optional[str]]:
    """
    Extract left/right from the FIRST packed dimension, e.g. '[7:0]' → ('7','0').
    Returns (None, None) for scalar.
    """
    if not packed:
        return None, None
    m = re.search(r'\[([^\]:]+):([^\]]+)\]', packed)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    # Single-bit explicit e.g. [0]
    m2 = re.search(r'\[(\d+)\]', packed)
    if m2:
        return m2.group(1), m2.group(1)
    return None, None


def build_ipxact(mod: SVModule, vendor: str, library: str, version: str) -> ET.Element:
    ET.register_namespace('ipxact', IPXACT_NS)
    ET.register_namespace('xsi', XSI_NS)

    root = ET.Element(_tag('component'), attrib={
        f'{{{XSI_NS}}}schemaLocation': SCHEMA_LOC,
    })

    # VLNV
    _sub(root, 'vendor',  vendor)
    _sub(root, 'library', library)
    _sub(root, 'name',    mod.name)
    _sub(root, 'version', version)

    # ── Bus Interfaces (one per interface port) ───────────────────────────
    if mod.interface_ports:
        bus_ifaces = _sub(root, 'busInterfaces')
        for ip in mod.interface_ports:
            bi = _sub(bus_ifaces, 'busInterface')
            _sub(bi, 'name', ip.name)
            # Placeholder busType VLNV — user must fill in
            bt = _sub(bi, 'busType')
            bt.set('vendor',  'unknown')
            bt.set('library', 'unknown')
            bt.set('name',    ip.interface_type)
            bt.set('version', '1.0')
            if ip.modport:
                am = _sub(bi, 'abstractionTypes')
                at = _sub(am, 'abstractionType')
                aref = _sub(at, 'abstractionRef')
                aref.set('vendor',  'unknown')
                aref.set('library', 'unknown')
                aref.set('name',    f'{ip.interface_type}_{ip.modport}')
                aref.set('version', '1.0')
            # Connection required
            _sub(bi, 'connectionRequired', 'false')

    # ── Model / Ports ─────────────────────────────────────────────────────
    model = _sub(root, 'model')
    views = _sub(model, 'views')
    view  = _sub(views, 'view')
    _sub(view, 'name', 'rtl')
    _sub(view, 'envIdentifier', ':systemverilog.rtl:')
    comp_inst = _sub(view, 'componentInstantiationRef', 'rtl_impl')

    insts = _sub(model, 'instantiations')
    ci    = _sub(insts, 'componentInstantiation')
    _sub(ci, 'name', 'rtl_impl')
    _sub(ci, 'language', 'systemVerilog')

    # Module parameters as moduleParameters
    if mod.parameters:
        mparams = _sub(ci, 'moduleParameters')
        for p in mod.parameters:
            mp = _sub(mparams, 'moduleParameter')
            _sub(mp, 'name',      p.name)
            _sub(mp, 'dataType',  p.data_type)
            if p.default_value:
                _sub(mp, 'value', p.default_value)
            mp.set('parameterId', f'param_{p.name}')

    ports_el = _sub(model, 'ports')

    for port in mod.ports:
        p_el = _sub(ports_el, 'port')
        _sub(p_el, 'name', port.name)
        wire = _sub(p_el, 'wire')
        _sub(wire, 'direction', direction_to_ipxact(port.direction))

        left, right = packed_dim_to_vectors(port.packed_dims)
        if left is not None:
            vecs = _sub(wire, 'vectors')
            vec  = _sub(vecs, 'vector')
            _sub(vec, 'left',  left)
            _sub(vec, 'right', right)

        # Unpacked dims → arrays
        if port.unpacked_dims:
            udim_matches = re.findall(r'\[([^\]]+)\]', port.unpacked_dims)
            if udim_matches:
                arrays = _sub(wire, 'arrays')
                for dim in udim_matches:
                    arr = _sub(arrays, 'array')
                    dm  = re.match(r'([^:]+):([^:]+)', dim)
                    if dm:
                        _sub(arr, 'left',  dm.group(1).strip())
                        _sub(arr, 'right', dm.group(2).strip())
                    else:
                        _sub(arr, 'left',  dim.strip())
                        _sub(arr, 'right', '0')

        # Wire type attribute for typedefs / structs
        if port.data_type and not _BUILTIN_TYPES.match(port.data_type):
            wire.set('userDataTypeRef', port.data_type)

    # Interface ports as transactional ports
    for ip in mod.interface_ports:
        p_el = _sub(ports_el, 'port')
        _sub(p_el, 'name', ip.name)
        trans = _sub(p_el, 'transactional')
        kind = _sub(trans, 'kind', 'tlm_port')
        if ip.modport:
            trans.set('initiative', ip.modport)

    # ── Parameters (component-level) ─────────────────────────────────────
    if mod.parameters:
        comp_params = _sub(root, 'parameters')
        for p in mod.parameters:
            param_el = _sub(comp_params, 'parameter')
            param_el.set('parameterId', f'param_{p.name}')
            param_el.set('resolve',     'user')
            _sub(param_el, 'name',  p.name)
            _sub(param_el, 'value', p.default_value or '0')

    # ── Typedefs as vendorExtensions ──────────────────────────────────────
    if mod.typedefs:
        vext = _sub(root, 'vendorExtensions')
        sv_types = ET.SubElement(vext, 'sv:typedefs',
            attrib={'xmlns:sv': 'http://example.com/sv-extensions'})
        for td in mod.typedefs:
            te = ET.SubElement(sv_types, 'sv:typedef')
            te.set('name', td.name)
            te.text = td.definition

    return root


# ---------------------------------------------------------------------------
# Pretty-print
# ---------------------------------------------------------------------------

def pretty_xml(root: ET.Element) -> str:
    raw = ET.tostring(root, encoding='unicode', xml_declaration=False)
    dom = minidom.parseString(raw)
    pretty = dom.toprettyxml(indent='  ', encoding='UTF-8').decode()
    # Remove the extra <?xml?> minidom adds (we add our own)
    pretty = re.sub(r'^<\?xml[^?]*\?>\n', '', pretty)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + pretty


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Convert SystemVerilog module header to IP-XACT 2022 XML')
    parser.add_argument('--input',   '-i', required=True,  help='Input .sv file')
    parser.add_argument('--output',  '-o', required=True,  help='Output .xml file')
    parser.add_argument('--vendor',        required=True,  help='VLNV vendor')
    parser.add_argument('--library',       required=True,  help='VLNV library')
    parser.add_argument('--version',       default='1.0',  help='VLNV version (default: 1.0)')
    args = parser.parse_args()

    src = Path(args.input).read_text(encoding='utf-8')
    mod = parse_sv_module(src)
    if mod is None:
        print(f'ERROR: No module declaration found in {args.input}', file=sys.stderr)
        sys.exit(1)

    print(f'  Parsed module  : {mod.name}')
    print(f'  Parameters     : {len(mod.parameters)}')
    print(f'  Ports          : {len(mod.ports)}')
    print(f'  Interface ports: {len(mod.interface_ports)}')
    print(f'  Typedefs       : {len(mod.typedefs)}')

    root = build_ipxact(mod, args.vendor, args.library, args.version)
    xml  = pretty_xml(root)
    Path(args.output).write_text(xml, encoding='utf-8')
    print(f'  Written        : {args.output}')


if __name__ == '__main__':
    main()
