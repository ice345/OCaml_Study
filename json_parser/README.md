# Simple JSON Parser in OCaml

这是一个完全使用 OCaml 编写的、零依赖（Zero-dependency）的 JSON 解析器。
本项目展示了如何利用 **代数数据类型 (ADT)**、**递归下降解析 (Recursive Descent Parsing)** 以及 **函数式组合子 (Functional Combinators)** 来构建健壮的系统软件。

## 📚 核心设计哲学 (Core Concepts)

### 1. 类型驱动建模 (Type-Driven Modeling)
JSON 的递归结构通过 OCaml 的 **ADT** 完美表达。数据结构本身即排除了非法的状态。

```ocaml
type json =
  | Null
  | Bool of bool
  | Int of int
  | Float of float
  | String of string
  | Array of json list     (* 递归定义：数组包含 JSON *)
  | Object of (string * json) list (* 递归定义：对象包含 JSON 值 *)
```

### 2. 管道式处理 (Pipeline Architecture)
解析过程被严格分层，每层只关注自己的职责：

```text
Raw String  --> [Lexer] --> Token List --> [Parser] --> AST (json type)
```

- **Lexer (词法分析)**: 处理字符流，识别数字、字符串、符号。
- **Parser (语法分析)**: 处理 Token 流，构建树状结构。

### 3. Monadic 查询接口
为了优雅地处理深度嵌套和潜在的空值（Null/Missing Key），提供了类似 `jq` 的链式查询操作符。利用 `Option Monad` 自动处理错误传播。

---

## 🛠 项目结构 (Project Structure)

```text
.
├── bin/
│   └── main.ml          # 可执行程序入口 (CLI demo)
├── lib/
│   ├── json_parser.ml   # 核心实现 (Lexer, Parser, Printer)
│   └── json_parser.mli  # 公开接口定义 (Abstraction Barrier)
├── test/
│   └── json_parser_test.ml # 全覆盖测试 (Alcotest framework)
├── dune-project         # 项目元数据
└── json_parser.opam     # 包定义
```

---

## 🚀 快速开始 (Quick Start)

### 1. 解析 (Parsing)

```ocaml
open Json_parser

let json_str = {| {"name": "OCaml", "version": 5.0} |}
let data = parse_json json_str
(* Result: Object [("name", String "OCaml"); ("version", Float 5.0)] *)
```

### 2. 序列化 (Serialization)

```ocaml
let str = to_string data
(* Result: "{\"name\": \"OCaml\", \"version\": 5.}" *)
```

### 3. 数据查询 (Querying with Operators)

使用自定义操作符安全地提取数据，无需手动匹配 `Some/None`。

- `|.` : 对象取值 (Access Object Field)
- `|@` : 数组取索引 (Access Array Index)

```ocaml
(* 假设 data 是 {"users": [{"name": "Alice"}]} *)

let name = Some data |. "users" |@ 0 |. "name"
(* Result: Some (String "Alice") *)

(* 错误处理自动化：路径不存在直接返回 None，不会崩溃 *)
let missing = Some data |. "users" |@ 99 |. "age"
(* Result: None *)
```

---

## 🧠 实现细节深度解析 (Implementation Details)

### 1. 词法分析 (Lexer)
位于 `lex` 函数。
- 使用 `char list` 模式匹配处理符号（`{`, `}`, `:` 等）。
- 使用 **Lookahead** 技术处理不定长 Token（数字和字符串）。
    - `lex_number`: 贪婪匹配数字、小数点、负号。
    - `lex_string`: 匹配直到闭合的双引号。

### 2. 语法分析 (Parser)
位于 `parse_value`及其互递归辅助函数。
采用 **递归下降 (Recursive Descent)** 算法：
- 每个解析函数消费一部分 Token，返回构建好的节点和**剩余的 Token**。
- `parse_array` 和 `parse_object` 利用递归处理嵌套结构，直到遇到闭合符号（`]` 或 `}`）。

### 3. 安全查询 (Accessors)
- `member`: 封装了 `List.assoc_opt`。
- `index`: 封装了 `List.nth_opt`，处理数组越界。
- 操作符 `|.` 和 `|@` 本质上是 `Option.bind` 的中缀应用，实现了 Railway Oriented Programming（铁轨导向编程）。

---

## 🧪 测试策略 (Testing Strategy)

本项目使用 **Alcotest** 框架，实现了高覆盖率测试。

### 运行测试
```bash
dune runtest
```

### 测试分类
1.  **Unit Tests**: 针对基础类型（Int, Float, String）的解析验证。
2.  **Error Handling**: 使用 `check_raises` 验证非法 JSON 会正确抛出异常。
3.  **Integration Tests (Round-Trip)**:
    - 验证 `Parse -> Stringify -> Parse` 的一致性。
    - 确保序列化和反序列化是完美的互逆操作。
    - 使用复杂的大型 JSON 用例验证深度嵌套处理能力。

---

## 📦 构建与安装 (Build & Install)

**前置依赖**:
- OCaml (>= 4.08)
- Dune
- Alcotest (仅测试需要)

```bash
# 安装依赖
opam install dune alcotest

# 构建项目
dune build

# 运行主程序
dune exec json_parser
```

---

> [!Tip]
> This project was built as a comprehensive exercise to master OCaml's type system, functional patterns, and tooling ecosystem. It demonstrates the transition from imperative thinking (loops/mutation) to functional thinking (recursion/immutability).
