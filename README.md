# RxZig 🚀

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Zig Version](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org/)
[![GitHub Stars](https://img.shields.io/github/stars/loicfm/RxZig?style=social)](https://github.com/loicfm/rxzig/stargazers)

**RxZig** is a **reactive programming library** for [Zig](https://ziglang.org/), inspired by [ReactiveX](https://reactivex.io/). It provides a powerful, efficient, and type-safe way to handle asynchronous and event-based programming in Zig.

---

## 🌟 Features
- **Reactive Streams**: Implement `Observable`, `Single`, and `Subject` patterns for reactive programming.
- **Operators**: A growing collection of operators like `map`, `filter`, and more operators to come.
- **Type Safety**: Leverage Zig's strong type system to ensure correctness at compile time.
- **Zero-Cost Abstractions**: Designed for performance with minimal runtime overhead.
- **Interoperability**: Works seamlessly with Zig's error handling and memory management.

---

## 📦 Installation

### Using the Zig Package Manager
Add RxZig as a dependency in your `build.zig`:
```zig
const rxzig = b.dependency("rxzig", .{
    .target = target,
    .optimize = optimize,
});
executable.root_module.addImport("rx", rxzig.module("rxzig"));
```

Or clone the repository directly:

```git clone https://github.com/loicfm/rxzig.git```

---
## 🧪 Testing
Tests are available to verify the correctness and functionality of the library. You can find them in:

- [test/observer_test.zig](https://github.com/loicfalk/rxzig/tree/main/test/observer_test.zig)
- [test/observable_test.zig](https://github.com/loicfalk/rxzig/tree/main/test/observable_test.zig)

### Run the tests
```zig build test```

---
## 📂 Examples
Basic examples are available to help you get started with RxZig:
- [examples/basic-example](https://github.com/loicfalk/rxzig/tree/main/examples/basic)

### Run the basic example
```zig build example-basic```

---

## 📜 License
This project is licensed under the **Apache License 2.0** - see the [LICENSE](https://github.com/loicfm/RxZig/blob/master/LICENSE) file for details.

---

## 🙌 Acknowledgments

- Inspired by [ReactiveX](https://reactivex.io/) and its implementations in other languages.
- Built with [Zig](https://ziglang.org/), a modern systems programming language.
- Thanks to all [contributors](https://github.com/loicfm/RxZig/graphs/contributors)!