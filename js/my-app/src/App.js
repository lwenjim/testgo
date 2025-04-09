import React, { useState } from 'react';
import './App.css';

function App() {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    setCount(count + 1);
  }; 

  var arr = [
    <h1 key={1}>菜鸟教程</h1>,
    <h2 key={2}>学的不仅是技术，更是梦想！</h2>,
  ];
  return (
    <div className="App">
      <h1>Click count: {count}</h1>
      <button onClick={handleClick}>Increase</button>
      <div>{arr}</div>
    </div>
  );
}

export default App;
