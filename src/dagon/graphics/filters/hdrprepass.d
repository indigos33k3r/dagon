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

module dagon.graphics.filters.hdrprepass;

import dlib.math.matrix;
import dagon.core.libs;
import dagon.core.ownership;
import dagon.graphics.postproc;
import dagon.graphics.framebuffer;
import dagon.graphics.rc;

/*
 * HDR prepass filter applies HDR effects that should be done before motion blur:
 * - Glow
 * - DoF (TODO)
 */

class PostFilterHDRPrepass: PostFilter
{
    private string vs = import("HDRPrepass.vs");
    private string fs = import("HDRPrepass.fs");

    override string vertexShader()
    {
        return vs;
    }

    override string fragmentShader()
    {
        return fs;
    }

    GLint perspectiveMatrixLoc;
    Matrix4x4f perspectiveMatrix;

    GLint fbBlurredLoc;
    GLint useGlowLoc;
    GLint glowBrightnessLoc;
    GLint glowMinLuminanceThresholdLoc;
    GLint glowMaxLuminanceThresholdLoc;

    bool glowEnabled = false;
    float glowBrightness = 0.5;
    float glowMinLuminanceThreshold = 0.0;
    float glowMaxLuminanceThreshold = 1.0;
    GLuint blurredTexture;

    this(Framebuffer inputBuffer, Framebuffer outputBuffer, Owner o)
    {
        super(inputBuffer, outputBuffer, o);

        perspectiveMatrixLoc = glGetUniformLocation(shaderProgram, "perspectiveMatrix");
        fbBlurredLoc = glGetUniformLocation(shaderProgram, "fbBlurred");
        useGlowLoc = glGetUniformLocation(shaderProgram, "useGlow");
        glowBrightnessLoc = glGetUniformLocation(shaderProgram, "glowBrightness");
        glowMinLuminanceThresholdLoc = glGetUniformLocation(shaderProgram, "glowMinLuminanceThreshold");
        glowMaxLuminanceThresholdLoc = glGetUniformLocation(shaderProgram, "glowMaxLuminanceThreshold");

        perspectiveMatrix = Matrix4x4f.identity;
    }

    override void bind(RenderingContext* rc)
    {
        super.bind(rc);

        glUniformMatrix4fv(perspectiveMatrixLoc, 1, GL_FALSE, perspectiveMatrix.arrayof.ptr);

        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, blurredTexture);
        glActiveTexture(GL_TEXTURE0);

        glUniform1i(fbBlurredLoc, 5);
        glUniform1i(useGlowLoc, glowEnabled);
        glUniform1f(glowBrightnessLoc, glowBrightness);
        glUniform1f(glowMinLuminanceThresholdLoc, glowMinLuminanceThreshold);
        glUniform1f(glowMaxLuminanceThresholdLoc, glowMaxLuminanceThreshold);
    }

    override void unbind(RenderingContext* rc)
    {
        glActiveTexture(GL_TEXTURE5);
        glBindTexture(GL_TEXTURE_2D, 0);
        glActiveTexture(GL_TEXTURE0);

        super.unbind(rc);
    }
}
