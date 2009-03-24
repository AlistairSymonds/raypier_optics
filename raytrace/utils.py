#    Copyright 2009, Teraview Ltd., Bryan Cole
#
#    This file is part of Raytrace.
#
#    Raytrace is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

import numpy
from enthought.tvtk.api import tvtk

def normaliseVector(a):
    """normalise a (3,) vector or a (n,3) array of vectors"""
    a= numpy.asarray(a)
    mag = numpy.sqrt((a**2).sum(axis=-1))
    return (a.T/mag).T

def transformPoints(t, pts):
    """Apply a vtkTransform to a numpy array of points"""
    out = tvtk.Points()
    t.transform_points(pts, out)
    return numpy.asarray(out)

def transformVectors(t, pts):
    """Apply a vtkTransform to a numpy array of vectors.
    I.e. ignore the translation component"""
    out = tvtk.DoubleArray(number_of_components=3)
    t.transform_vectors(pts, out)
    return numpy.asarray(out)

def transformNormals(t, pts):
    """Apply a vtkTransform to a numpy array of normals.
    I.e. ignore the translation component and normalise
    the resulting magnitudes"""
    out = tvtk.DoubleArray(number_of_components=3)
    t.transform_normals(pts, out)
    return numpy.asarray(out)

dotprod = lambda a,b: (a*b).sum(axis=-1)[...,numpy.newaxis]

def Convert_to_SP(input_v, normal_v, E1_vector, E1_amp, E2_amp):
    """
    All inputs are 2D arrays
    """
    cross = numpy.cross
    
    E2_vector = cross(input_v, E1_vector)
    
    v = cross(input_v, normal_v)
    S_vector = numpy.where(numpy.all(v==0, axis=1).reshape(-1,1)*numpy.ones(3), 
                           normaliseVector(E1_vector),
                           normaliseVector(v) )
    
    v = cross(input_v, S_vector)
    P_vector = normaliseVector(v)
    
    S_amp = E1_amp*dotprod(E1_vector,S_vector) + E2_amp*dotprod(E2_vector, S_vector)
                
    P_amp = E1_amp*dotprod(E1_vector,P_vector) + E2_amp*dotprod(E2_vector, P_vector)
    
    return S_amp, P_amp, S_vector, P_vector
