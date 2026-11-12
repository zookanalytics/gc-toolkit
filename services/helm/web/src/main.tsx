import React from 'react';
import { createRoot } from 'react-dom/client';
import { Page } from './rigboard/Board';
import './fonts.css';
import './rigboard/board.css';

const container = document.getElementById('root');
if (!container) {
  throw new Error('helm: #root is missing from index.html');
}

createRoot(container).render(
  <React.StrictMode>
    <Page />
  </React.StrictMode>,
);
