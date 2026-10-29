// The smallest program that links against hnoss. Exists so the build always
// has at least one example to compile.
package main

import "core:fmt"
import hnoss "../.."

main :: proc() {
	fmt.println("hnoss", hnoss.VERSION)
}
