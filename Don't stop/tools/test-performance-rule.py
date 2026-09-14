import unittest
from performance_rule import regression_details
class RuleTests(unittest.TestCase):
    def flagged(self,base,next): return bool(regression_details(dict(p95=base,p99=base),dict(p95=next,p99=next)))
    def test_reported_regression(self): self.assertTrue(self.flagged(38.67,50.46))
    def test_absolute_even_with_small_percentage(self): self.assertTrue(self.flagged(100,109))
    def test_relative_even_with_small_absolute(self): self.assertTrue(self.flagged(10,13))
    def test_noise(self): self.assertFalse(self.flagged(4,5))
    def test_improvement(self): self.assertFalse(self.flagged(50,38))
    def test_p95_alone(self): self.assertTrue(regression_details(dict(p95=10,p99=40),dict(p95=14,p99=40)))
if __name__=='__main__': unittest.main()
