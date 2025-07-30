import "@hotwired/turbo-rails"
import "controllers"

(function() {
  'use strict';
  
  if (window.dataDripInitialized) {
    return;
  }
  window.dataDripInitialized = true;
  
  function ready(fn) {
    if (document.readyState !== 'loading') {
      fn();
    } else {
      document.addEventListener('DOMContentLoaded', fn);
    }
  }
  
  function handleConfirmations() {
    document.removeEventListener('click', handleClick);
    document.addEventListener('click', handleClick);
  }
  
  function handleClick(event) {
    var confirmElement = event.target.closest('[data-confirm]');
    
    if (confirmElement) {
      event.preventDefault();
      event.stopPropagation();
      
      var message = confirmElement.getAttribute('data-confirm');
      var disableText = confirmElement.getAttribute('data-disable-with');
      
      if (confirm(message)) {
        var form = confirmElement.closest('form');
        var submitButton = form ? form.querySelector('input[type="submit"], button[type="submit"]') : null;
        
        if (disableText && submitButton) {
          submitButton.disabled = true;
          if (submitButton.tagName === 'INPUT') {
            submitButton.value = disableText;
          } else {
            submitButton.textContent = disableText;
          }
        }
        
        if (form) {
          form.submit();
        }
      }
    }
  }
  
  ready(handleConfirmations);
})(); 

