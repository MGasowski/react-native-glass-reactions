import App from './App';
import DemoApp from './DemoApp';
import OpacityProbe from './OpacityProbe';
import { SCREEN } from './demo-config';

/**
 * Screen selection lives here rather than in index.js so the switch is typed
 * and so `./App` keeps its meaning: the benchmark screen the automated suites
 * drive. Flipping SCREEN is a source edit, matching how TRIGGERS_ENABLED works
 * for the A/B, and for the same reason: both arms then run the same code path.
 */
export default function Entry() {
  if (SCREEN === 'demo') return <DemoApp />;
  if (SCREEN === 'opacity') return <OpacityProbe />;
  return <App />;
}
