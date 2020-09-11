package bake

command: {
  image: #Dubo & {
    args: {
      BUILD_TITLE: "Athens"
      BUILD_DESCRIPTION: "A dubo image for Athens based on \(args.DEBOOTSTRAP_SUITE) (\(args.DEBOOTSTRAP_DATE))"
    }
  }
}
