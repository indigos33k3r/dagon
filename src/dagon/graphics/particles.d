/*
Copyright (c) 2017-2018 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.graphics.particles;

import std.random;
import std.algorithm;

import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.interpolation;
import dlib.math.utils;
import dlib.image.color;
import dlib.container.array;

import derelict.opengl;
import dagon.logics.behaviour;
import dagon.logics.entity;
import dagon.graphics.texture;
import dagon.graphics.view;
import dagon.graphics.rc;
import dagon.graphics.material;
import dagon.graphics.mesh;

struct Particle
{
    Color4f startColor;
    Color4f color;
    Vector3f position;
    Vector3f acceleration;
    Vector3f velocity;
    Vector3f gravityVector;
    Vector2f scale;
    float lifetime;
    float time;
    bool move;
    bool active;
}

abstract class ForceField: Behaviour
{
    this(Entity e, ParticleSystem psys)
    {
        super(e);
        psys.addForceField(this);
    }

    void upadte(double dt)
    {
    }

    void affect(ref Particle p);
}

class Attractor: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = max(EPSILON, r.length);
        p.acceleration += r * -g / (d * d);
    }
}

class Deflector: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = max(EPSILON, r.length);
        p.acceleration += r * g / (d * d);
    }
}

class Vortex: ForceField
{
    float g1;
    float g2;

    this(Entity e, ParticleSystem psys, float tangentMagnitude, float normalMagnitude)
    {
        super(e, psys);
        g1 = tangentMagnitude;
        g2 = normalMagnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f direction = entity.transformation.forward;
        float proj = dot(p.position, direction);
        Vector3f pos = entity.position + direction * proj;
        Vector3f r = p.position - pos;
        float d = max(EPSILON, r.length);
        Vector3f t = lerp(r, cross(r, direction), 0.25f);
        p.acceleration += direction * g2 - t * g1 / (d * d);
    }
}

class BlackHole: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = r.length;
        if (d <= 0.001f)
            p.time = p.lifetime;
        else
            p.acceleration += r * -g / (d * d);
    }
}

class ColorChanger: ForceField
{
    Color4f color;
    float outerRadius;
    float innerRadius;

    this(Entity e, ParticleSystem psys, Color4f color, float outerRadius, float innerRadius)
    {
        super(e, psys);
        this.color = color;
        this.outerRadius = outerRadius;
        this.innerRadius = innerRadius;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float t = clamp((r.length - innerRadius) / outerRadius, 0.0f, 1.0f);
        p.color = lerp(color, p.color, t);
    }
}

class ParticleSystem: Behaviour
{
    Particle[] particles;
    DynamicArray!ForceField forceFields;
    
    float airFrictionDamping = 0.98f;
    
    float minLifetime = 1.0f;
    float maxLifetime = 3.0f;
    
    float minSize = 0.25f;
    float maxSize = 1.0f;
    Vector2f scaleStep = Vector2f(0, 0);
    
    float initialPositionRandomRadius = 0.0f;
    
    float minInitialSpeed = 1.0f;
    float maxInitialSpeed = 5.0f;
    
    Vector3f initialDirection = Vector3f(0, 1, 0);
    float initialDirectionRandomFactor = 1.0f;
    
    Color4f startColor = Color4f(1, 0.5f, 0, 1);
    Color4f endColor = Color4f(1, 1, 1, 0);
    
    bool emitting = true;
    
    bool haveParticlesToDraw = false;
    
    Vector3f[4] vertices;
    Vector2f[4] texcoords;
    uint[3][2] indices;
    
    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;
    
    Matrix4x4f invViewMatRot;
    
    Material material;

    this(Entity e, uint numParticles)
    {
        super(e);
        
        particles = New!(Particle[])(numParticles);
        foreach(ref p; particles)
        {
            resetParticle(p);
        }
        
        vertices[0] = Vector3f(-0.5f, 0.5f, 0);
        vertices[1] = Vector3f(-0.5f, -0.5f, 0);
        vertices[2] = Vector3f(0.5f, -0.5f, 0);
        vertices[3] = Vector3f(0.5f, 0.5f, 0);
        
        texcoords[0] = Vector2f(0, 0);
        texcoords[1] = Vector2f(0, 1);
        texcoords[2] = Vector2f(1, 1);
        texcoords[3] = Vector2f(1, 0);
        
        indices[0][0] = 0;
        indices[0][1] = 1;
        indices[0][2] = 2;
        
        indices[1][0] = 0;
        indices[1][1] = 2;
        indices[1][2] = 3;
        
        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 3, vertices.ptr, GL_STATIC_DRAW); 

        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
    
        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, 3, GL_FLOAT, GL_FALSE, 0, null);
    
        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, 2, GL_FLOAT, GL_FALSE, 0, null);

        glBindVertexArray(0);
    }

    ~this()
    {
        Delete(particles);
        forceFields.free();
    }
    
    void addForceField(ForceField ff)
    {
        forceFields.append(ff);
    }

    void resetParticle(ref Particle p)
    {
        if (initialPositionRandomRadius > 0.0f)
        {
            float randomDist = uniform(0.0f, initialPositionRandomRadius);
            p.position = entity.absolutePosition + randomUnitVector3!float * randomDist;
        }
        else
            p.position = entity.absolutePosition;
        Vector3f r = randomUnitVector3!float;

        float initialSpeed;
        if (maxInitialSpeed > minInitialSpeed)
            initialSpeed = uniform(minInitialSpeed, maxInitialSpeed);
        else
            initialSpeed = maxInitialSpeed;
        p.velocity = lerp(initialDirection, r, initialDirectionRandomFactor) * initialSpeed;
        
        if (maxLifetime > minLifetime)
            p.lifetime = uniform(minLifetime, maxLifetime);
        else
            p.lifetime = maxLifetime;
        p.gravityVector = Vector3f(0, -1, 0);
        
        float s;
        if (maxSize > maxSize)
            s = uniform(maxSize, maxSize);
        else
            s = maxSize;
            
        p.scale = Vector2f(s, s);
        p.time = 0.0f;
        p.move = true;
        p.startColor = startColor;
        p.color = p.startColor;
    }
    
    void updateParticle(ref Particle p, double dt)
    {
        p.time += dt;
        if (p.move)
        {
            p.acceleration = Vector3f(0, 0, 0);
               
            foreach(ref ff; forceFields)
            {
                ff.affect(p);
            }
                
            p.velocity += p.acceleration * dt;
            p.velocity = p.velocity * airFrictionDamping;

            p.position += p.velocity * dt;
        }

        float t = p.time / p.lifetime;
        p.color.a = lerp(1.0f, 0.0f, t);
            
        p.scale = p.scale + scaleStep * dt;
    }
    
    override void update(double dt)
    {
        haveParticlesToDraw = false;
        foreach(ref p; particles)
        {
            if (p.active)
            {
                if (p.time < p.lifetime)
                {
                    updateParticle(p, dt);
                    haveParticlesToDraw = true;
                }
                else
                    p.active = false;
            }
            else if (emitting)
            {
                resetParticle(p);
                p.active = true;
            }
        }
    }
    
    override void render(RenderingContext* rc)
    {        
        if (haveParticlesToDraw)
        {            
            foreach(ref p; particles)
            if (p.time < p.lifetime)
            {
                Matrix4x4f modelViewMatrix = 
                    rc.viewMatrix * 
                    translationMatrix(p.position) * 
                    rc.invViewRotationMatrix * 
                    scaleMatrix(Vector3f(p.scale.x, p.scale.y, 1.0f));
                
                RenderingContext rcLocal = *rc;
                rcLocal.modelViewMatrix = modelViewMatrix;

                if (material)
                    material.bind(&rcLocal);
        
                glBindVertexArray(vao);
                glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
                glBindVertexArray(0);
        
                if (material)
                    material.unbind(&rcLocal);
            }
        }
    }
}
