pub const vshader =
    \\ #version 330 core 
    \\
    \\ layout (location = 0) in vec3 position;
    \\ //layout (location = 1) in vec3 color;
    \\ layout (location = 1) in vec2 vertexUV;
    \\
    \\ out vec2 UV;
    \\
    \\ uniform mat4 Projection;
    \\ uniform mat4 Model;
    \\ uniform mat4 Camera;
    \\
    \\ void main()
    \\ {
    \\    mat4 MVP = Projection * Camera * Model;
    \\    gl_Position = MVP * vec4(position, 1.0);
    \\
    \\    UV = vertexUV;
    \\ }
;

pub const map_vshader =
    \\ #version 330 core 
    \\
    \\ layout (location = 0) in vec3 position;
    \\ layout (location = 1) in vec2 vertexUV;
    \\ layout (location = 2) in vec2 maskUV;
    \\
    \\ out vec2 UV;
    \\ uniform mat4 Projection;
    \\ uniform mat4 Model;
    \\ uniform mat4 Camera;
    \\
    \\ void main()
    \\ {
    \\    mat4 MVP = Projection * Camera * Model;
    \\    gl_Position = MVP * vec4(position, 1.0);
    \\
    \\    UV = vertexUV;
    \\ }
;

pub const fshader =
    \\#version 330 core
    \\uniform sampler2D texture_sampler;
    \\in vec2 UV;
    \\out vec4 color;
    \\
    \\void main()
    \\{
    \\  color = texture(texture_sampler, UV);
    \\}
;

pub const fshader_text =
    \\#version 330 core
    \\uniform sampler2D texture_sampler;
    \\in vec2 UV;
    \\out vec4 color;
    \\
    \\void main()
    \\{
    \\  float alpha = texture(texture_sampler, UV).r;
    \\  color = vec4(vec3(1.0, 1.0, 1.0), alpha);// texture(texture_sampler, UV);
    \\}
;
