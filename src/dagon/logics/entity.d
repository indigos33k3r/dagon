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

module dagon.logics.entity;

import dlib.core.memory;
import dlib.container.array;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.quaternion;

import derelict.opengl;

import dagon.core.interfaces;
import dagon.core.ownership;
import dagon.core.event;
import dagon.logics.controller;
import dagon.logics.behaviour;
import dagon.graphics.material;
import dagon.graphics.rc;

Matrix4x4f rotationPart(Matrix4x4f m)
{
    Matrix4x4f res = m;
    res.a14 = 0.0f;
    res.a24 = 0.0f;
    res.a34 = 0.0f;
    return m;
}

enum Attach
{
    Parent,
    Camera
}

class Entity: Owner
{
    uint id;
    uint groupID = 0;

    struct BehaviourListEntry
    {
        Behaviour behaviour;
        bool valid;
    }

    DynamicArray!BehaviourListEntry behaviours;
    Drawable drawable;
    EventManager eventManager;
    
    Entity parent = null;
    DynamicArray!Entity children;

    Vector3f position;
    Quaternionf rotation;
    Vector3f scaling;

    Matrix4x4f transformation;
    Matrix4x4f invTransformation;
    
    Matrix4x4f absoluteTransformation;
    Matrix4x4f invAbsoluteTransformation;
    
    Matrix4x4f prevTransformation;
    Matrix4x4f prevAbsoluteTransformation;

    EntityController controller;
    DefaultEntityController defaultController;

    Material material;
    RenderingContext rcLocal;

    bool visible = true;
    bool castShadow = true;
    Attach attach = Attach.Parent;
    
    bool useMotionBlur = true;
    
    bool clearZbuffer = false;
    
    int layer = 1;

    this(EventManager emngr, Owner owner)
    {
        super(owner);
        eventManager = emngr;

        transformation = Matrix4x4f.identity;
        invTransformation = Matrix4x4f.identity;

        position = Vector3f(0, 0, 0);
        rotation = Quaternionf.identity;
        scaling = Vector3f(1, 1, 1);

        defaultController = New!DefaultEntityController(this);
        controller = defaultController;
        
        absoluteTransformation = Matrix4x4f.identity;
        invAbsoluteTransformation = Matrix4x4f.identity;
        prevTransformation = Matrix4x4f.identity;
        prevAbsoluteTransformation = Matrix4x4f.identity;
    }
        
    this(Entity parent)
    {
        this(parent.eventManager, parent);
        parent.children.append(this);
        this.parent = parent;
    }

    ~this()
    {
        behaviours.free();
        children.free();
    }
    
    Vector3f absolutePosition()
    {
        if (parent)
            return position * parent.transformation;
        else
            return position;
    }

    Behaviour addBehaviour(Behaviour b)
    {
        behaviours.append(BehaviourListEntry(b, true));
        return b;
    }

    void removeBehaviour(Behaviour b)
    {
        foreach(i, ble; behaviours)
        {
            if (ble.behaviour is b)
                behaviours[i].valid = false;
        }
    }

    bool hasBehaviour(T)()
    {
        return this.behaviour!T() !is null;
    }

    T behaviour(T)()
    {
        T result = null;

        foreach(i, ble; behaviours)
        {
            T b = cast(T)ble.behaviour;
            if (b)
            {
                result = b;
                break;
            }
        }

        return result;
    }

    void processEvents()
    {
        foreach(i, ble; behaviours)
        {
            if (ble.valid)
            {
                ble.behaviour.processEvents();
            }
        }
        
        foreach(child; children)
        {
            child.processEvents();
        }
    }

    void update(double dt)
    {
        prevTransformation = transformation;
    
        if (controller)
            controller.update(dt);
        
        if (parent)
        {
            absoluteTransformation = parent.absoluteTransformation * transformation;
            prevAbsoluteTransformation = parent.prevAbsoluteTransformation * prevTransformation;
        }
        else
        {
            absoluteTransformation = transformation;
            prevAbsoluteTransformation = prevTransformation;
        }
        
        foreach(i, ble; behaviours)
        {
            if (ble.valid)
            {
                ble.behaviour.update(dt);
            }
        }
        
        foreach(child; children)
        {
            child.update(dt);
        }

        if (drawable)
            drawable.update(dt);
    }

    void render(RenderingContext* rc)
    {
        if (!visible)
            return;

        foreach(i, ble; behaviours)
        {
            if (ble.valid)
                ble.behaviour.bind();
        }

        rcLocal = *rc;
        
        if (attach == Attach.Camera)
        {         
            rcLocal.modelMatrix = translationMatrix(rcLocal.cameraPosition) * transformation;
            rcLocal.invModelMatrix = invTransformation * translationMatrix(-rcLocal.cameraPosition); 

            if (useMotionBlur)
                rcLocal.prevModelViewProjMatrix = rcLocal.projectionMatrix * (rcLocal.prevViewMatrix * (translationMatrix(rcLocal.prevCameraPosition) * prevTransformation));
            else
                rcLocal.prevModelViewProjMatrix = rcLocal.projectionMatrix * (rcLocal.viewMatrix * (translationMatrix(rcLocal.cameraPosition) * transformation));
        }
        else
        {
            rcLocal.modelMatrix = absoluteTransformation;
            rcLocal.invModelMatrix = invAbsoluteTransformation;
            
            if (useMotionBlur)
                rcLocal.prevModelViewProjMatrix = rcLocal.projectionMatrix * (rcLocal.prevViewMatrix * prevAbsoluteTransformation);
            else
                rcLocal.prevModelViewProjMatrix = rcLocal.projectionMatrix * (rcLocal.viewMatrix * absoluteTransformation);
        }
        
        rcLocal.modelViewMatrix = rcLocal.viewMatrix * rcLocal.modelMatrix;
        rcLocal.normalMatrix = rcLocal.modelViewMatrix.inverse.transposed;
        
        rcLocal.blurModelViewProjMatrix = rcLocal.projectionMatrix * rcLocal.modelViewMatrix;
        
        if (useMotionBlur)
            rcLocal.blurMask = 1.0f;
        else
            rcLocal.blurMask = 0.0f;

        if (rcLocal.overrideMaterial)
            rcLocal.overrideMaterial.bind(&rcLocal);
        else if (material)
            material.bind(&rcLocal);

        if (clearZbuffer)
            glClear(GL_DEPTH_BUFFER_BIT);

        if (drawable)
            drawable.render(&rcLocal);

        if (rcLocal.overrideMaterial)
            rcLocal.overrideMaterial.unbind(&rcLocal);
        else if (material)
            material.unbind(&rcLocal);

        foreach(i, ble; behaviours)
        {
            if (ble.valid)
                ble.behaviour.render(&rcLocal);
        }
        
        foreach(child; children)
        {
            child.render(&rcLocal);
        }

        foreach_reverse(i, ble; behaviours.data)
        {
            if (ble.valid)
                ble.behaviour.unbind();
        }
    }
}

unittest
{
    class B1 : Behaviour
    {
        this(Entity e) {super(e);}
    }
    class B2 : Behaviour
    {
        this(Entity e) {super(e);}
    }
    auto e = New!Entity(null, null);
    New!B1(e);
    assert(e.hasBehaviour!B1());
    New!B2(e);
    assert(e.hasBehaviour!B2());

    auto b1 = e.behaviour!B1();
    assert(b1);
    auto b2 = e.behaviour!B2();
    assert(b2);

    // sets `valid` to false, but does not delete the behaviour
    e.removeBehaviour(b1);
    // ... so hasBehaviour reports true
    assert(e.hasBehaviour!B1());
}
