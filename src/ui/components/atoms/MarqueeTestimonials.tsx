import React from 'react';
import { motion } from 'framer-motion';
import TestimonialCard from './TestimonialCard';
import { User } from 'lucide-react';

interface Testimonial {
  quote: string;
  author: string;
}

interface MarqueeTestimonialsProps {
  testimonials: Testimonial[];
  direction?: 'left' | 'right';
  speed?: number;
}

const MarqueeTestimonials = ({ 
  testimonials, 
  direction = 'left',
  speed = 25
}: MarqueeTestimonialsProps) => {
  // Duplicate the testimonials for a seamless loop
  const doubledTestimonials = [...testimonials, ...testimonials];
  
  return (
    <div className="relative overflow-hidden w-full">
      <motion.div 
        className="flex gap-6"
        animate={{
          x: direction === 'left' 
            ? [0, -testimonials.length * 320] 
            : [-testimonials.length * 320, 0]
        }}
        transition={{
          duration: testimonials.length * speed,
          ease: "linear",
          repeat: Infinity,
          repeatType: "loop"
        }}
      >
        {doubledTestimonials.map((testimonial, index) => (
          <div key={index} className="flex-shrink-0 w-[280px]">
            <TestimonialCard
              quote={testimonial.quote}
              author={testimonial.author}
              userIcon={<User className="w-4 h-4 text-white" />}
            />
          </div>
        ))}
      </motion.div>
    </div>
  );
};

export default MarqueeTestimonials;
