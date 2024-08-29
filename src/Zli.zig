const std = @import("std");
const Allocator = std.mem.Allocator;

const Zli = @This();

// TODO: Neues Konzept:
// Options und Arguments haben getrennte Strukturen
// .setOptions(...):
//      - param definition: anytype:
//          - fieldnames = long-names
//          - inner struct contain required data-type field and optional short and description fields
//      - sets struct:
//          - has function to get an option by name
// .setArgument(...):
//      - basically the same as options, likely simpler
// lazily parsed on first get
// core parser holds references to both
