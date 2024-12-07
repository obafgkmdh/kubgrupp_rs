use std::{
    collections::HashMap,
    f32::consts::PI,
    io::{BufReader, Read}, iter::Peekable,
};

use anyhow::{anyhow, bail, Result};
use ash::vk;
use glam::{Mat4, Vec3};
use obj::Obj;
use serde::Deserialize;
use toml::{Table, Value};

use crate::scene::{type_lexer::{Token, TokenIter}, Scene};

#[derive(Clone)]
pub struct MeshScene {
    pub camera_mat: Mat4,
    pub lights: Vec<Light>,
    pub instances: Vec<Instance>,
    pub meshes: Vec<Obj>,

    pub miss_shader: Shader,
    pub hit_shaders: Vec<Shader>,
}

#[derive(Clone)]
pub struct Camera {
    // matrix from world space to camera space
    pub view: Mat4,

    // matrix from camera to clip space
    pub perspective: Mat4,
}

#[derive(Clone)]
pub enum Light {
    Point {
        color: Vec3,
        position: Vec3,
    },
    Area {
        color: Vec3,
        mesh: Obj,
        transform: Mat4,
    },
    Spotlight {
        color: Vec3,
        transform: Mat4,
        angle: f32,
    },
}

#[derive(Clone)]
pub struct Shader {
    pub code: vk::ShaderModule,
}

#[derive(Clone)]
pub struct Instance {
    pub transform: Mat4,

    // its just like aris fr
    pub mesh_i: usize,
    pub brdf_i: usize,
    pub brdf_params: Vec<u8>,
    pub alignment: usize,
}

enum ShaderType {
    Float,
    Vec3,
    UInt,
    Int,
    Array(Box<ShaderType>, u64),
}

pub enum MeshSceneUpdate {
    NewView(Mat4),
    NewAspectRatio(f32),
    NewFovDegrees(f32),
}

impl Scene for MeshScene {
    type Updates = [MeshSceneUpdate];
}

impl MeshScene {
    pub const MAX_LIGHTS: u32 = 1000;

    pub fn load_from(mut reader: impl Read) -> Result<Self> {
        let mut toml_conf = String::new();
        reader.read_to_string(&mut toml_conf)?;

        let conf: Table = toml_conf.parse()?;

        let camera = Self::parse_camera(conf);

        Ok(Self {
            camera_mat: Mat4::IDENTITY,
            lights: Vec::new(),
            instances: Vec::new(),
            meshes: Vec::new(),
            miss_shader: Shader { code: vk::ShaderModule::null() },
            hit_shaders: Vec::new(),
        })
    }

    fn parse_transform(transform_str: &str) -> Result<Mat4> {
        let mut transform = Mat4::IDENTITY;

        for line in transform_str.lines() {
            let mut tokens = line.trim().split_ascii_whitespace();

            let Some(action) = tokens.next() else {
                // empty means we ignore
                continue;
            };

            // match on action (omg thats a cinema term)
            match action {
                "identity" => transform = Mat4::IDENTITY,
                "translate" => {
                    let x = Self::parse_f32(&mut tokens)?;
                    let y = Self::parse_f32(&mut tokens)?;
                    let z = Self::parse_f32(&mut tokens)?;

                    if tokens.next().is_some() {
                        bail!("transform requires only x y z, but extra info was provided");
                    }

                    let translation = Mat4::from_translation(Vec3::new(x, y, z));
                    transform = translation * transform;
                }
                "rotate" => {
                    let angle = Self::parse_f32(&mut tokens)? * PI / 180f32;
                    let x = Self::parse_f32(&mut tokens)?;
                    let y = Self::parse_f32(&mut tokens)?;
                    let z = Self::parse_f32(&mut tokens)?;
                    let axis = Vec3::new(x, y, z);

                    if tokens.next().is_some() {
                        bail!("rotate requires only angle x y z, but extra info was provided");
                    }

                    let rotation = Mat4::from_axis_angle(axis, angle);
                    transform = rotation * transform;
                }
                "scale" => {
                    let x = Self::parse_f32(&mut tokens)?;
                    let y = Self::parse_f32(&mut tokens)?;
                    let z = Self::parse_f32(&mut tokens)?;
                    let scale = Vec3::new(x, y, z);

                    if tokens.next().is_some() {
                        bail!("scale requires only x y z, but extra info was provided");
                    }

                    let scale = Mat4::from_scale(scale);
                    transform = scale * transform;
                }
                "lookat" => {
                    let eye_x = Self::parse_f32(&mut tokens)?;
                    let eye_y = Self::parse_f32(&mut tokens)?;
                    let eye_z = Self::parse_f32(&mut tokens)?;
                    let eye = Vec3::new(eye_x, eye_y, eye_z);

                    let center_x = Self::parse_f32(&mut tokens)?;
                    let center_y = Self::parse_f32(&mut tokens)?;
                    let center_z = Self::parse_f32(&mut tokens)?;
                    let center = Vec3::new(center_x, center_y, center_z);

                    let up_x = Self::parse_f32(&mut tokens)?;
                    let up_y = Self::parse_f32(&mut tokens)?;
                    let up_z = Self::parse_f32(&mut tokens)?;
                    let up = Vec3::new(up_x, up_y, up_z);

                    if tokens.next().is_some() {
                        bail!("lookat requires only eye_x eye_y eye_z center_x center_y center_z up_x up_y up_z, but extra info was provided");
                    }

                    let lookat = Mat4::look_at_lh(eye, center, up);
                    transform = lookat;
                }
                _ if action.starts_with("#") => (),
                x => bail!("invalid transform action: {x}"),
            };
        }

        Ok(transform)
    }

    fn parse_f32<'a>(mut tokens: impl Iterator<Item = &'a str>) -> Result<f32> {
        let num = tokens
            .next()
            .ok_or(anyhow!("float expected but not found"))?;
        Ok(num.parse()?)
    }

    fn parse_type_str(type_str: &str) -> Result<ShaderType> {
        let mut tokens = TokenIter::new(type_str).peekable();
        Self::parse_type(&mut tokens)
    }

    fn parse_type<'a>(tokens: &mut Peekable<TokenIter<'a>>) -> Result<ShaderType> {
        let lookahead = tokens.peek().ok_or(anyhow!("incomplete type - no tokens remaining"))?;
        let parsed_type = match lookahead {
            Token::LSqBracket => Self::parse_array(tokens)?,
            Token::Semicolon => todo!(),
            Token::Typename(s) => Self::parse_simple_type(tokens)?,
            Token::Integer(int) => bail!("type should never start with integer token, but started with one: {int}"),
            Token::RSqBracket => bail!("type should never start with right square bracket"),
            Token::LexerError(_) => {
                let Token::LexerError(error) = tokens.next().unwrap() else {
                    panic!("failed to match lexer error that was just matched on");
                };

                return Err(error);
            },
        };

        Ok(parsed_type)
    }

    fn parse_array<'a>(mut tokens: &mut Peekable<TokenIter<'a>>) -> Result<ShaderType> {
        if !matches!(tokens.next().ok_or(anyhow!("no next token"))?, Token::LSqBracket) {
            bail!("no [ found for start of array");
        }

        let parsed_type = Self::parse_type(tokens)?;

        if !matches!(tokens.next().ok_or(anyhow!("no next token"))?, Token::Semicolon) {
            bail!("no semicolon found after parsing array type")
        }

        let Token::Integer(array_size) = tokens.next().ok_or(anyhow!("no next token"))? else {
            bail!("array size should be a constant unsigned integer")
        };

        if !matches!(tokens.next().ok_or(anyhow!("no next token"))?, Token::RSqBracket) {
            bail!("no ] found for end of array")
        }

        Ok(ShaderType::Array(Box::new(parsed_type), array_size))
    }

    fn parse_simple_type<'a>(mut tokens: &mut Peekable<TokenIter<'a>>) -> Result<ShaderType> {
        let the_token = tokens.next().ok_or(anyhow!("no next token"))?;
        let Token::Typename(typename) = the_token else {
            bail!("token was not a typename: {:?}", the_token)
        };
        Ok(match typename {
            "float" => ShaderType::Float,
            "int" => ShaderType::Int,
            "uint" => ShaderType::UInt,
            "vec3" => ShaderType::Vec3,
            s => bail!("invalid typename: {s}")
        })
    }

    fn parse_camera(conf: Table) -> Result<Camera> {
        let Some(Value::Table(camera_table)) = conf.get("camera") else {
            bail!("camera must be a table")
        };

        let fov = camera_table
            .get("fov")
            .ok_or(anyhow!("camera.fov must be set"))?;
        let fov = match fov {
            Value::Integer(x) => *x as f32,
            Value::Float(x) => *x as f32,
            _ => bail!("camera.fov must be an integer or float"),
        };

        // convert to radians
        let fov_radians = fov * PI / 180f32;

        // use 1 as default aspect ratio
        // ideally this will never actually be used since it will be updated immediately after window creation
        let perspective = Mat4::perspective_lh(fov_radians, 1f32, 0f32, 1000f32);

        let Value::String(view_str) = camera_table
            .get("view")
            .ok_or(anyhow!("camera.view must be set"))?
        else {
            bail!("camera.view must be a transform string")
        };
        let view = Self::parse_transform(view_str)?;

        Ok(Camera { view, perspective })
    }
}

#[cfg(test)]
mod tests {
    use glam::{Vec3, Vec4};

    use super::MeshScene;

    #[test]
    fn parse_lookat() {
        let camera_mat = MeshScene::parse_transform(
            "
        # this is a comment that should be ignored
        lookat 3 2 1   0 0 0   0 0 1
        ",
        )
        .expect("failed to parse");

        let point = Vec4::new(0f32, 0f32, 0f32, 1f32);
        let point_cam = camera_mat * point;

        let eye = Vec3::new(3f32, 2f32, 1f32);
        let dist = eye.dot(eye).sqrt();

        assert!((point_cam.z - dist) < 2e-4, "point_cam.z: {}, ||eye - origin||: {}", point_cam.z, dist);
    }
}
