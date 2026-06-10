package docker.security

import rego.v1

deny contains msg if {
  not has_user

  msg := "Dockerfile does not define a non-root USER"
}

has_user if {
  instruction := input[_]
  lower(instruction.Cmd) == "user"
}