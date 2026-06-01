# Masa Programming Language

This is an experiment on a strongly typed, procedural, multi-return, opinionated programming langauge that transpiles down to JavaScipt and runs with an embedded [Bun](https://bun.sh/) runtime.

## Initial Syntax & Feautres Idea

```
pacakge main

import "core:fmt"                                        // Masa built-in library
import "jslib:zod"                                       // JS managed libraries in node_modules

System_User :: struct {
    name: string `json:"userName"`                       // Go inspired tags support
    age: number
}

get_schema :: fn(self: System_User) -> zod.ZodObject {   // Return type is inferable
    return zod.object({                                  // Direct JavaScript library "unsafe" call
        name: zod.string(),
    })
}

main :: fn() {                                           // Could be `async fn`
    fmt.println("Hello Masa!")

    user := System_User {                                // Runtime variables can only be mutable
        name: "John",
        age: 34,
    }

    user_schema := user.get_schema()                     // `self: System_User` gives us method syntax
                                                         // but only if defined in the same package

    parsed_user: dict = user_schema.parse(user) `dict` is a type alias for `map[string]any`
}

color: Color = match status {
	.Loading => .Yellow,
	.Success => .Green,
	.Failed => .Red,
}
```
## Project State

Latest language features supported can be found in [latest.masa](./masa/latest.masa).

| Note: Langauge is in early development and language syntax and features are prone to change.