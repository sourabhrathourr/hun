// A light shiki theme in the site's warm palette: ink text on the raised
// cream code background, persimmon for keywords, the "running" green for
// strings, and a quiet slate for commands and functions.

const ink = "#1F1B16";
const ink2 = "#4F483F";
const ink3 = "#6E675C";
const persimmon = "#B8461D";
const rust = "#8F3E1F";
const green = "#3B7049";
const slate = "#355C7A";
const amber = "#8A5A12";

export const hunPaperTheme = {
  name: "hun-paper",
  type: "light" as const,
  colors: {
    "editor.background": "#FFFCF6",
    "editor.foreground": ink,
  },
  settings: [
    { settings: { foreground: ink, background: "#FFFCF6" } },
    {
      scope: ["comment", "punctuation.definition.comment", "string.comment"],
      settings: { foreground: ink3, fontStyle: "italic" },
    },
    {
      scope: [
        "keyword",
        "keyword.control",
        "storage",
        "storage.type",
        "storage.modifier",
        "keyword.operator.new",
        "keyword.operator.expression",
        "keyword.operator.logical.python",
        "variable.language",
      ],
      settings: { foreground: persimmon },
    },
    {
      scope: ["string", "string.quoted", "string.template", "string.unquoted.plain.out.yaml", "markup.inline.raw"],
      settings: { foreground: green },
    },
    {
      scope: [
        "constant.numeric",
        "constant.language",
        "constant.character",
        "constant.other.option",
        "constant.other",
        "support.constant",
        "keyword.other.unit",
      ],
      settings: { foreground: amber },
    },
    {
      scope: [
        "entity.name.function",
        "support.function",
        "meta.function-call entity.name.function",
        "entity.name.command",
        "support.function.builtin.shell",
        "entity.name.type",
        "support.type",
        "support.class",
        "entity.name.class",
      ],
      settings: { foreground: slate },
    },
    {
      scope: [
        "entity.name.tag",
        "entity.name.tag.yaml",
        "support.type.property-name",
        "meta.object-literal.key",
        "entity.other.attribute-name",
        "variable.other.property",
        "meta.mapping.key",
        "keyword.other.definition.ini",
        "entity.name.tag.toml",
        "support.type.property-name.toml",
      ],
      settings: { foreground: rust },
    },
    {
      scope: ["variable", "variable.other", "variable.parameter", "meta.definition.variable"],
      settings: { foreground: ink },
    },
    {
      scope: ["variable.other.normal.shell", "punctuation.definition.variable.shell", "variable.other.env"],
      settings: { foreground: rust },
    },
    {
      scope: [
        "punctuation",
        "meta.brace",
        "punctuation.separator",
        "punctuation.terminator",
        "punctuation.definition.string",
        "keyword.operator",
        "punctuation.definition.block.sequence.item.yaml",
      ],
      settings: { foreground: ink2 },
    },
    { scope: ["markup.heading", "entity.name.section"], settings: { foreground: ink, fontStyle: "bold" } },
    { scope: ["markup.bold"], settings: { fontStyle: "bold" } },
    { scope: ["markup.italic"], settings: { fontStyle: "italic" } },
    { scope: ["markup.inserted"], settings: { foreground: green } },
    { scope: ["markup.deleted"], settings: { foreground: "#A3352A" } },
    { scope: ["invalid"], settings: { foreground: "#A3352A" } },
  ],
};
