import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import { DrillProvider } from './drill';
import './styles.css';

const container = document.getElementById('root');
if (!container) {
  throw new Error('helm: #root is missing from index.html');
}

createRoot(container).render(
  <React.StrictMode>
    {/* The drill plane resolves its supervisor origin once, here, and shares one
        event stream with everything below. */}
    <DrillProvider>
      <App />
    </DrillProvider>
  </React.StrictMode>,
);
