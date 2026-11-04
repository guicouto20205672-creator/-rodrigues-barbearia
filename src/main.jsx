import React from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.jsx';
import './styles.css';

class AppErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(error) {
    return { error };
  }
  componentDidCatch(error, info) {
    console.error('Erro ao carregar Rodrigues Barbearia:', error, info);
  }
  render() {
    if (this.state.error) {
      return <main style={{minHeight:'100vh',background:'#111',color:'#eee',padding:'32px',fontFamily:'Arial,sans-serif'}}>
        <h1 style={{color:'#c5a66d'}}>Não foi possível abrir o sistema</h1>
        <p>Ocorreu um erro ao carregar a interface.</p>
        <pre style={{whiteSpace:'pre-wrap',overflowWrap:'anywhere',background:'#222',padding:'16px',borderRadius:'8px'}}>{String(this.state.error?.message || this.state.error)}</pre>
        <button onClick={()=>window.location.reload()} style={{padding:'12px 18px',background:'#c5a66d',border:0}}>Tentar novamente</button>
      </main>;
    }
    return this.props.children;
  }
}
createRoot(document.getElementById('root')).render(<AppErrorBoundary><App/></AppErrorBoundary>);
