# Raymarching Demo

This project is a demonstration of **raymarching** techniques developed for the **Computer Graphics** course.

## Demo Scene

The demo scene contains an approximate model of an **internal combustion engine** rendered using raymarching.

The engine speed can be controlled during execution:

* **Left Mouse Button**: Increase RPM
* **Right Mouse Button**: Decrease RPM

## Camera Controls

* **Mouse**: Look around
* **W / A / S / D**: Move the camera
* **Mouse Wheel**: Adjust movement speed
* **Ctrl + Mouse Wheel**: Adjust the camera Field of View (FOV)

## Building the Project

This project requires **Zig 0.15.2**.

After installing the correct Zig version, build and run the project with:

```sh
zig build run
```

## Dependencies

The project only relies on two external libraries:

* A **GLFW wrapper** for window and input management.
* An **OpenGL loader** for accessing OpenGL functions.
