target "default" {
  inherits = ["shared"]
  args = {
    BUILD_TITLE = "Go Proxy"
    BUILD_DESCRIPTION = "A dubo image for Athens"
  }
  tags = [
    "dubodubonduponey/goproxy",
  ]
}
